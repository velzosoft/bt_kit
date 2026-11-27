import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../core/bluetooth_uuid.dart';
import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../core/operation_queue.dart';
import '../channels/byte_channel.dart';
import '../models/bond_state.dart';
import '../models/characteristic_properties.dart';
import '../models/connection_priority.dart';
import '../models/bluetooth_connection_state.dart';
import '../models/disconnect_reason.dart';
import '../models/distance.dart';
import '../models/notify_mode.dart';
import '../models/permission.dart';
import '../models/phy.dart';
import '../platform/central_backend.dart';
import '../platform/channel_backend.dart';
import 'bonding.dart';
import 'device_host.dart';
import 'native_types.dart';
import 'peripheral_event.dart';

part 'gatt.dart';
part 'subscription.dart';

/// Default timeouts for one-shot operations.
abstract final class Timeouts {
  static const connect = Duration(seconds: 30);
  static const discovery = Duration(seconds: 30);
  static const gatt = Duration(seconds: 10);

  /// Pairing can wait for the user to confirm a code.
  static const bond = Bonding.timeout;
}

/// A remote BLE device in the peripheral role.
///
/// Every GATT operation is queued per peripheral, has a timeout and accepts
/// a [CancelToken]. Pending operations fail with [DisconnectedException]
/// when the link drops.
final class Peripheral {
  Peripheral._(this._backend, this._host) {
    _backend.connectionStates.listen(_onConnectionState);
    _backend.notifications.listen(_onNotification);
    _backend.updates.listen(_onUpdate);
  }

  final PeripheralBackend _backend;
  final DeviceHost _host;
  late final _queue = OperationQueue(log: BtLog.gatt, label: id);
  late final _bonding = Bonding(
    _backend.bond,
    _host,
    _queue,
    id,
    onChange: (state) => _host.report(BondChanged(this, state)),
  );
  var _watchingBond = false;
  var _measuring = false;
  var _autoConnect = false;
  final _subscriptions = <Object, _Subscription>{};
  final _characteristics = <Object, GattCharacteristic>{};
  final _servicesChanged = StreamController<void>.broadcast();
  var _services = const <GattService>[];

  /// Android: the MAC address. iOS: a UUID that CoreBluetooth assigns per
  /// app and keeps stable for that app.
  String get id => _backend.id;

  /// The GAP name the system knows for this device, if any.
  String? get name => _backend.name;

  PeripheralHandle get native => _backend.native;

  BluetoothConnectionState get connectionState => _backend.connectionState;

  Stream<BluetoothConnectionState> get connectionStates =>
      _backend.connectionStates;

  bool get isConnected => connectionState == BluetoothConnectionState.connected;

  /// Why the last connection ended, or why the last attempt failed.
  DisconnectReason? get lastDisconnect => _backend.lastDisconnect;

  /// The ATT MTU in effect: 23 until a larger one is negotiated.
  int get mtu => _backend.mtu;

  /// MTU changes. Android reports each negotiation, including the 517 that
  /// Android 14 and later negotiate unprompted. iOS reports once after
  /// connecting.
  Stream<int> get mtuChanges => _backend.updates.expand(
    (update) => [if (update case MtuUpdate(:final mtu)) mtu],
  );

  /// PHY changes, whether this app or the peripheral asked for them
  /// (Android).
  Stream<PhyInfo> get phyChanges => _backend.updates.expand(
    (update) => [if (update case PhyUpdate(:final phy)) phy],
  );

  /// GAP name changes (iOS).
  Stream<String?> get nameChanges => _backend.updates.expand(
    (update) => [if (update case NameUpdate(:final name)) name],
  );

  /// Fires when the peripheral changes its GATT database.
  ///
  /// The affected services leave [services] at once: Android invalidates
  /// all of them, iOS only those the change touched. Operations on their
  /// attributes fail with [AttributeInvalidatedException], and their
  /// subscriptions end with it. Call [discoverServices] to see the new
  /// database.
  Stream<void> get servicesChanged => _servicesChanged.stream;

  /// The valid services found by the last [discoverServices].
  List<GattService> get services => _services;

  /// Whether this device is bonded with the peripheral (Android). iOS does
  /// not report bonds, so there it is always [BondState.none].
  BondState get bondState => _bonding.state;

  Stream<BondState> get bondStates => _bonding.states;

  /// Whether the last [connect] asked for `autoConnect`.
  bool get autoConnect => _autoConnect;

  /// Connects to the peripheral.
  ///
  /// With [autoConnect], the platform keeps trying until the device is in
  /// range (and on iOS reconnects after a drop) instead of failing fast;
  /// pass a [timeout] that matches.
  ///
  /// With [mtu], the MTU is requested right after connecting, within
  /// [timeout], where the app can choose it (`capabilities.requestMtu`).
  /// Android 13 needs this for throughput; Android 14 and later negotiate
  /// 517 on their own, and iOS negotiates by itself. A peripheral that
  /// refuses leaves the connection at the MTU it had.
  Future<void> connect({
    bool autoConnect = false,
    int? mtu,
    Duration timeout = Timeouts.connect,
    CancelToken? cancelToken,
  }) async {
    await _host.ensureReady(const {BluetoothPermission.connect});
    if (isConnected) return;
    _autoConnect = autoConnect;
    try {
      await _queue.run(
        'connect',
        () async {
          await _backend.connect(autoConnect: autoConnect);
          if (mtu != null && _host.capabilities.requestMtu) {
            await _negotiateMtu(mtu);
          }
        },
        timeout: timeout,
        cancelToken: cancelToken,
      );
    } on OperationTimeoutException {
      await _backend.disconnect();
      rethrow;
    } on OperationCancelledException {
      await _backend.disconnect();
      rethrow;
    }
  }

  Future<void> _negotiateMtu(int mtu) async {
    try {
      await _backend.requestMtu(mtu);
    } on GattException catch (e) {
      _keptMtu(e);
    } on NativeOperationException catch (e) {
      _keptMtu(e);
    }
  }

  void _keptMtu(BluetoothException error) => BtLog.gatt.warning(
    () => '$id: the MTU request after connecting failed, keeping $mtu: $error',
  );

  /// Disconnects immediately; queued operations fail with
  /// [DisconnectedException].
  Future<void> disconnect() => _backend.disconnect();

  /// Discovers every service, characteristic and descriptor.
  ///
  /// Replaces [services] with new objects, whose [GattCharacteristic.lastValue]
  /// starts empty.
  Future<List<GattService>> discoverServices({
    Duration timeout = Timeouts.discovery,
    CancelToken? cancelToken,
  }) async {
    final discovered = await _run(
      'discoverServices',
      _backend.discoverServices,
      timeout,
      cancelToken,
    );
    final services = [
      for (final service in discovered) GattService._(this, service),
    ];
    final byKey = {for (final service in services) service._key: service};
    for (final service in services) {
      service._resolveIncluded(byKey);
    }
    _characteristics
      ..clear()
      ..addAll({
        for (final service in services)
          for (final c in service.characteristics) c._key: c,
      });
    return _services = services;
  }

  /// Finds a discovered characteristic.
  GattCharacteristic? characteristic(
    BluetoothUuid service,
    BluetoothUuid characteristic,
  ) {
    for (final s in _services.where((s) => s.uuid == service)) {
      for (final c in s.characteristics.where(
        (c) => c.uuid == characteristic,
      )) {
        return c;
      }
    }
    return null;
  }

  Future<int> readRssi({
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) => _run('readRssi', _backend.readRssi, timeout, cancelToken);

  /// Requests an ATT MTU and returns the MTU in effect.
  ///
  /// iOS negotiates the MTU itself; there this returns the current one.
  Future<int> requestMtu(
    int mtu, {
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) =>
      _run('requestMtu', () => _backend.requestMtu(mtu), timeout, cancelToken);

  /// The longest value one write can carry.
  int maximumWriteLength({bool withResponse = true}) =>
      _backend.maximumWriteLength(withResponse: withResponse);

  /// Asks for a shorter or longer connection interval (Android).
  ///
  /// Completes once Android accepted the request; Android does not report
  /// when the new parameters take effect.
  Future<void> requestConnectionPriority(
    ConnectionPriority priority, {
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) async {
    _require(
      _host.capabilities.connectionPriority,
      'connectionPriority',
      'This platform chooses connection parameters itself',
    );
    await _run(
      'requestConnectionPriority ${priority.name}',
      () => _backend.requestConnectionPriority(priority),
      timeout,
      cancelToken,
    );
  }

  /// Asks for the PHYs this connection should use, and returns the ones in
  /// effect afterwards (Android).
  ///
  /// The peripheral may refuse, so the result can differ from the request.
  Future<PhyInfo> setPreferredPhy({
    required Set<Phy> tx,
    required Set<Phy> rx,
    PhyCoding coding = PhyCoding.none,
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) async {
    _checkPhys(tx);
    _checkPhys(rx);
    return _run(
      'setPreferredPhy',
      () => _backend.setPreferredPhy(tx, rx, coding),
      timeout,
      cancelToken,
    );
  }

  /// The PHYs this connection uses (Android).
  Future<PhyInfo> readPhy({
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) async {
    _require(_host.capabilities.phy, 'phy', 'This platform hides the PHY');
    return _run('readPhy', _backend.readPhy, timeout, cancelToken);
  }

  /// Clears Android's cache of the peripheral's GATT database, so that the
  /// next [discoverServices] reads it from the peripheral; returns whether
  /// Android accepted (Android).
  ///
  /// Only peripherals that change their database without sending Services
  /// Changed need this. It calls `BluetoothGatt.refresh()`, a non-SDK
  /// interface that a later Android release may block; check
  /// `capabilities.gattCacheRefresh`. Once cleared, [services] is empty and
  /// operations on the old attributes fail with
  /// [AttributeInvalidatedException] until [discoverServices] runs again.
  Future<bool> clearGattCache({
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) async {
    _require(
      _host.capabilities.gattCacheRefresh,
      'gattCacheRefresh',
      'This platform keeps its GATT cache current itself',
    );
    final cleared = await _run(
      'clearGattCache',
      _backend.clearGattCache,
      timeout,
      cancelToken,
    );
    if (cleared) _invalidate(null, report: false);
    return cleared;
  }

  /// Opens an L2CAP channel to [psm], which the peripheral publishes
  /// (often in a GATT characteristic).
  ///
  /// [secure] requires an encrypted link on Android; on iOS the publishing
  /// side decides.
  Future<L2capChannel> openL2capChannel(
    int psm, {
    bool secure = true,
    Duration timeout = Timeouts.connect,
    CancelToken? cancelToken,
  }) async {
    Future<L2capChannelBackend>? opening;
    try {
      final channel = await _run(
        'openL2capChannel $psm',
        () => opening = _backend.openL2capChannel(psm, secure: secure),
        timeout,
        cancelToken,
      );
      return createL2capChannel(channel);
    } on BluetoothException catch (e) {
      if (e is OperationTimeoutException || e is OperationCancelledException) {
        unawaited(
          opening?.then((channel) => channel.close(), onError: (Object _) {}),
        );
      }
      rethrow;
    }
  }

  /// Pairs with the peripheral and completes once it is bonded (Android).
  ///
  /// Android may show a pairing dialog, so the default [timeout] is long.
  /// Pairing that ends without a bond fails with [BondException]. iOS pairs
  /// on its own when the app first uses an encrypted attribute; there this
  /// fails with [UnsupportedFeatureException].
  Future<void> createBond({
    Duration timeout = Timeouts.bond,
    CancelToken? cancelToken,
  }) => _bonding.create(timeout: timeout, cancelToken: cancelToken);

  /// Removes the bond and returns whether it is gone (Android).
  ///
  /// Android 16 (API 36) and later remove it through a companion device
  /// association, which the system may first ask the user to confirm.
  /// Where apps cannot remove bonds (`capabilities.removeBond` is false),
  /// this opens the Bluetooth settings instead and completes when the user
  /// returns; watch [bondStates] for the outcome.
  Future<bool> removeBond({
    Duration timeout = Timeouts.bond,
    CancelToken? cancelToken,
  }) => _bonding.remove(timeout: timeout, cancelToken: cancelToken);

  /// Measures the distance to the peripheral until the subscription is
  /// cancelled. One measurement runs per peripheral at a time.
  ///
  /// [DistanceMethod.channelSounding] needs Bluetooth 6.0 on both sides
  /// (`capabilities.channelSounding`): on Android 16 and later the
  /// peripheral must be bonded, on iOS 27 and later connected.
  /// [DistanceMethod.rssi] estimates from signal strength
  /// (`capabilities.rssiRanging`, Android). Android also needs the
  /// [BluetoothPermission.ranging] permission. Errors arrive as
  /// [RangingException].
  Stream<DistanceMeasurement> measureDistance({
    DistanceMethod method = DistanceMethod.channelSounding,
    MeasurementRate rate = MeasurementRate.normal,
  }) {
    late final StreamController<DistanceMeasurement> controller;
    StreamSubscription<DistanceMeasurement>? samples;
    void stop() {
      if (samples != null) _measuring = false;
      samples = null;
    }

    controller = StreamController<DistanceMeasurement>(
      onListen: () async {
        try {
          _checkDistance(method);
          await _host.ensureReady(const {
            BluetoothPermission.connect,
            BluetoothPermission.ranging,
          });
          if (!controller.hasListener) return;
          if (_measuring) {
            throw const RangingException(
              'A distance measurement is already running for this '
              'peripheral',
            );
          }
          _measuring = true;
          BtLog.ranging.info(() => '$id: measuring by ${method.name}');
          samples = _backend
              .measureDistance(method, rate)
              .listen(
                (sample) {
                  BtLog.ranging.fine(() => '$id: $sample');
                  controller.add(sample);
                },
                onError: controller.addError,
                onDone: () {
                  stop();
                  unawaited(controller.close());
                },
              );
        } on BluetoothException catch (e) {
          controller.addError(e);
          await controller.close();
        }
      },
      onCancel: () {
        final active = samples;
        stop();
        return active?.cancel();
      },
    );
    return controller.stream;
  }

  void _checkDistance(DistanceMethod method) {
    final capabilities = _host.capabilities;
    switch (method) {
      case DistanceMethod.channelSounding:
        _require(
          capabilities.channelSounding,
          'channelSounding',
          'Channel Sounding needs Bluetooth 6.0 hardware and Android 16 or '
              'iOS 27',
        );
      case DistanceMethod.rssi:
        _require(
          capabilities.rssiRanging,
          'rssiRanging',
          'RSSI ranging needs Android 16 (API 36) or later',
        );
    }
  }

  /// Runs [action] while holding this peripheral's operation queue, so that
  /// Layer 1 calls on [native] never overlap a Layer 2 operation.
  ///
  /// The queue stays held until [action] finishes, even after [timeout].
  Future<T> exclusive<T>(
    Future<T> Function() action, {
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) => _queue.run(
    'exclusive',
    action,
    timeout: timeout,
    cancelToken: cancelToken,
  );

  @override
  String toString() => 'Peripheral($id)';

  Future<T> _run<T>(
    String name,
    Future<T> Function() operation,
    Duration timeout,
    CancelToken? cancelToken,
  ) {
    if (!isConnected) return Future.error(const DisconnectedException());
    return _queue.run(
      name,
      operation,
      timeout: timeout,
      cancelToken: cancelToken,
    );
  }

  /// Runs an operation on an attribute of [service], which must still be
  /// valid when the operation starts.
  Future<T> _runOn<T>(
    GattService service,
    String name,
    Future<T> Function() operation,
    Duration timeout,
    CancelToken? cancelToken,
  ) {
    if (service.isInvalidated) return Future.error(_invalidated);
    return _run(
      name,
      () {
        if (service.isInvalidated) throw _invalidated;
        return operation();
      },
      timeout,
      cancelToken,
    );
  }

  void _checkPhys(Set<Phy> phys) {
    final capabilities = _host.capabilities;
    _require(capabilities.phy, 'phy', 'This platform chooses the PHY itself');
    if (phys.isEmpty) throw ArgumentError('Name at least one PHY');
    if (phys.contains(Phy.le2M)) {
      _require(capabilities.le2MPhy, 'le2MPhy', 'No LE 2M PHY on this device');
    }
    if (phys.contains(Phy.leCoded)) {
      _require(
        capabilities.leCodedPhy,
        'leCodedPhy',
        'No LE Coded PHY on this device',
      );
    }
  }

  void _onConnectionState(BluetoothConnectionState state) {
    final reason = state == BluetoothConnectionState.disconnected
        ? lastDisconnect
        : null;
    BtLog.gatt.info(
      () => '$id: ${state.name}${reason == null ? '' : ' ($reason)'}',
    );
    if (state == BluetoothConnectionState.connected && !_watchingBond) {
      _watchingBond = true;
      _bonding.watch();
    }
    if (state == BluetoothConnectionState.disconnected) {
      if (_watchingBond) {
        _watchingBond = false;
        _bonding.unwatch();
      }
      final error = DisconnectedException(
        'The peripheral disconnected',
        reason,
      );
      _queue.failWaiting(error);
      for (final subscription in _subscriptions.values) {
        subscription.end(error);
      }
      _subscriptions.clear();
    }
    _host.report(ConnectionChanged(this, state, reason));
  }

  void _onNotification(ValueNotification notification) {
    final characteristic = _characteristics[notification.key];
    BtLog.gatt.finer(
      () => '$id: ${characteristic?.uuid} pushed ${hex(notification.value)}',
    );
    characteristic?._lastValue.update(notification.value);
    _subscriptions[notification.key]?.add(notification.value);
  }

  void _onUpdate(LinkUpdate update) {
    switch (update) {
      case MtuUpdate(:final mtu):
        BtLog.gatt.info(() => '$id: MTU $mtu');
        _host.report(MtuChanged(this, mtu));
      case PhyUpdate(:final phy):
        BtLog.gatt.info(() => '$id: $phy');
      case NameUpdate(:final name):
        _host.report(NameChanged(this, name));
      case ServicesUpdate(:final invalidated):
        _invalidate(invalidated);
    }
  }

  void _invalidate(List<Object>? keys, {bool report = true}) {
    final stale = [
      for (final service in _services)
        if (keys == null || keys.contains(service._key)) service,
    ];
    BtLog.gatt.info(() => '$id: ${stale.length} services invalidated');
    for (final service in stale) {
      service._invalidated = true;
      for (final characteristic in service.characteristics) {
        _characteristics.remove(characteristic._key);
        _subscriptions.remove(characteristic._key)?.end(_invalidated);
      }
    }
    _services = [
      for (final service in _services)
        if (!service.isInvalidated) service,
    ];
    if (!report) return;
    _servicesChanged.add(null);
    _host.report(ServicesChanged(this));
  }

  static const _invalidated = AttributeInvalidatedException(
    'The peripheral changed its services; discover them again',
  );

  static void _require(bool supported, String feature, String message) {
    if (!supported) throw UnsupportedFeatureException(feature, message);
  }
}

/// Creates the [Peripheral] for a backend; used by `BtKit` only.
Peripheral createPeripheral(PeripheralBackend backend, DeviceHost host) =>
    Peripheral._(backend, host);

Never _noNative() =>
    throw UnsupportedError('Fake Bluetooth objects have no native object');
