import 'dart:async';
import 'dart:typed_data';

import 'package:objective_c/objective_c.dart' as objc;

import '../../central/native_types.dart';
import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../core/native_handle.dart';
import '../../models/connection_priority.dart';
import '../../models/bluetooth_connection_state.dart';
import '../../models/disconnect_reason.dart';
import '../../models/distance.dart';
import '../../models/notify_mode.dart';
import '../../models/phy.dart';
import '../../native/ios/bindings.dart';
import '../bond_backend.dart';
import '../central_backend.dart';
import '../channel_backend.dart';
import '../request_slot.dart';
import '../unsupported.dart';
import 'ios_central.dart';
import 'ios_streams.dart';
import 'objc_conversions.dart';

enum _Request {
  connect,
  discover,
  read,
  write,
  notify,
  readDescriptor,
  writeDescriptor,
  rssi,
  l2cap,
}

/// A GATT client for one peripheral, built on `CBPeripheral`.
///
/// Platform quirks handled here:
/// * Delegate properties are weak, so this client owns its delegate.
/// * Reads and notifications both arrive through
///   `peripheral:didUpdateValueForCharacteristic:error:`; a value is a read
///   result only while a read of that characteristic is pending.
/// * Writes without response have no callback; they wait for
///   `canSendWriteWithoutResponse` instead.
/// * Writing the Client Characteristic Configuration descriptor raises an
///   Objective-C exception; notifications go through `setNotifyValue`.
/// * Discovery is four nested rounds (services, included services,
///   characteristics, descriptors), collapsed here into one request.
///   Service discovery finds primary services only; secondary services are
///   found as included services.
/// * There is no MTU callback; the MTU is derived from the longest write
///   without response.
/// * Channel Sounding callbacks exist from iOS 27; on older versions the
///   delegate must not implement them at all.
final class IosGattClient implements PeripheralBackend {
  IosGattClient(this._central, this.peripheral, this.id) {
    peripheral.delegate = _delegate;
  }

  static const _disconnectGrace = Duration(seconds: 5);
  static const _defaultMtu = 23;

  final IosCentral _central;
  final CBPeripheral peripheral;
  final _requests = RequestSlot();
  final _states = StreamController<BluetoothConnectionState>.broadcast();
  final _notifications = StreamController<ValueNotification>.broadcast();
  final _updates = StreamController<LinkUpdate>.broadcast();

  var _state = BluetoothConnectionState.disconnected;
  DisconnectReason? _lastDisconnect;
  var _discovered = <int, CBService>{};
  var _pendingIncludes = 0;
  var _pendingDiscoveries = 0;
  Completer<void>? _readyToWrite;
  Future<void>? _disconnecting;
  var _attempt = 0;
  StreamController<DistanceMeasurement>? _distance;

  /// Cancelled Channel Sounding sessions whose completion has not arrived;
  /// their late callbacks must not end a newer session.
  var _cancelledSessions = 0;

  static final _channelSounding = CBPeripheralDelegate$Builder
      .peripheral_didReceiveChannelSoundingProcedureResults_error_
      .isAvailable;

  late final CBPeripheralDelegate _delegate = CBPeripheralDelegate.implement(
    peripheral_didDiscoverServices_: (_, error) => _servicesDiscovered(error),
    peripheral_didDiscoverIncludedServicesForService_error_: (
      _,
      service,
      error,
    ) => _includedDiscovered(service, error),
    peripheral_didDiscoverCharacteristicsForService_error_: (
      _,
      service,
      error,
    ) => _characteristicsDiscovered(service, error),
    peripheral_didDiscoverDescriptorsForCharacteristic_error_: (_, _, error) =>
        _descriptorsDiscovered(error),
    peripheral_didModifyServices_: (_, invalidated) => _updates.add(
      ServicesUpdate(listOf(invalidated, (service) => keyOf(service))),
    ),
    peripheralDidUpdateName_: (_) => _updates.add(NameUpdate(name)),
    peripheral_didUpdateValueForCharacteristic_error_: (
      _,
      characteristic,
      error,
    ) => _valueUpdated(characteristic, error),
    peripheral_didWriteValueForCharacteristic_error_: (
      _,
      characteristic,
      error,
    ) => _finish(_Request.write, error, null, key: keyOf(characteristic)),
    peripheral_didUpdateNotificationStateForCharacteristic_error_: (
      _,
      characteristic,
      error,
    ) => _finish(_Request.notify, error, null, key: keyOf(characteristic)),
    peripheral_didUpdateValueForDescriptor_error_: (_, descriptor, error) =>
        _finish(
          _Request.readDescriptor,
          error,
          () => bytesOf(descriptor.value),
        ),
    peripheral_didWriteValueForDescriptor_error_: (_, _, error) =>
        _finish(_Request.writeDescriptor, error, null),
    peripheral_didReadRSSI_error_: (_, rssi, error) =>
        _finish(_Request.rssi, error, () => rssi.intValue),
    peripheralIsReadyToSendWriteWithoutResponse_: (_) =>
        _readyToWrite?.complete(),
    peripheral_didOpenL2CAPChannel_error_: (_, channel, error) =>
        error != null || channel == null
        ? _requests.fail(
            _Request.l2cap,
            error == null
                ? const ConnectionException('No L2CAP channel was opened')
                : errorOf(error, 'openL2CAPChannel'),
          )
        : _requests.complete(_Request.l2cap, IosL2capChannel(channel, id)),
    peripheral_didReceiveChannelSoundingProcedureResults_error_:
        _channelSounding
        ? (_, results, error) => _measured(results, error)
        : null,
    peripheral_didCompleteChannelSoundingSession_: _channelSounding
        ? (_, error) => _sessionCompleted(error)
        : null,
  );

  @override
  final String id;

  @override
  String? get name => peripheral.name?.toDartString();

  @override
  PeripheralHandle get native => IosHandle(peripheral);

  @override
  BluetoothConnectionState get connectionState => _state;

  @override
  Stream<BluetoothConnectionState> get connectionStates => _states.stream;

  @override
  DisconnectReason? get lastDisconnect => _lastDisconnect;

  @override
  final BondBackend bond = const UnsupportedBond(
    'iOS pairs on its own when the app first uses an encrypted attribute',
  );

  @override
  Stream<ValueNotification> get notifications => _notifications.stream;

  @override
  Stream<LinkUpdate> get updates => _updates.stream;

  @override
  int get mtu => _state == BluetoothConnectionState.connected
      ? maximumWriteLength(withResponse: false) + 3
      : _defaultMtu;

  CBPeripheral get _connected => _state == BluetoothConnectionState.connected
      ? peripheral
      : throw const DisconnectedException();

  @override
  Future<void> connect({required bool autoConnect}) async {
    final attempt = ++_attempt;
    await _disconnecting;
    if (attempt != _attempt) throw const OperationCancelledException();
    _setState(BluetoothConnectionState.connecting);
    final connected = _requests.begin<void>(_Request.connect).future;
    _central.connect(this, autoConnect: autoConnect);
    return connected;
  }

  @override
  Future<void> disconnect() {
    _attempt++;
    return _disconnecting ??= _disconnect().whenComplete(
      () => _disconnecting = null,
    );
  }

  Future<void> _disconnect() async {
    if (_state == BluetoothConnectionState.disconnected) return;
    _setState(BluetoothConnectionState.disconnecting);
    final disconnected = _states.stream.firstWhere(
      (s) => s == BluetoothConnectionState.disconnected,
    );
    _central.cancelConnection(this);
    await disconnected.timeout(
      _disconnectGrace,
      onTimeout: () {
        BtLog.gatt.warning(
          () =>
              '$id: iOS did not report the disconnection; ending the '
              'link after ${millis(_disconnectGrace)}',
        );
        _disconnected(
          DisconnectCause.requested,
          null,
          const DisconnectedException('Disconnected'),
        );
        return BluetoothConnectionState.disconnected;
      },
    );
  }

  /// Takes the state of a peripheral iOS restored, without reporting it as
  /// a change.
  void restore() {
    _state = switch (peripheral.state) {
      CBPeripheralState.CBPeripheralStateConnected =>
        BluetoothConnectionState.connected,
      CBPeripheralState.CBPeripheralStateConnecting =>
        BluetoothConnectionState.connecting,
      CBPeripheralState.CBPeripheralStateDisconnecting =>
        BluetoothConnectionState.disconnecting,
      CBPeripheralState.CBPeripheralStateDisconnected =>
        BluetoothConnectionState.disconnected,
    };
  }

  void didConnect() {
    _setState(BluetoothConnectionState.connected);
    _requests.complete(_Request.connect, null);
    _updates.add(MtuUpdate(mtu));
  }

  void didFailToConnect(objc.NSError? error) => _disconnected(
    DisconnectCause.failedToConnect,
    error,
    ConnectionException(
      'Connection failed',
      nativeCode: error?.code,
      nativeError: error,
    ),
  );

  void didDisconnect(objc.NSError? error) {
    final cause = iosDisconnectCause(_cbErrorCode(error), from: _state);
    _disconnected(
      cause,
      error,
      cause == DisconnectCause.failedToConnect
          ? ConnectionException(
              'Connection failed',
              nativeCode: error?.code,
              nativeError: error,
            )
          : const DisconnectedException('The peripheral disconnected'),
    );
  }

  void adapterTurnedOff() => _disconnected(
    DisconnectCause.adapterOff,
    null,
    _state == BluetoothConnectionState.connecting
        ? const ConnectionException('Bluetooth turned off')
        : const DisconnectedException('Bluetooth turned off'),
  );

  @override
  Future<List<DiscoveredService>> discoverServices() {
    final result = _requests
        .begin<List<DiscoveredService>>(_Request.discover)
        .future;
    _connected.discoverServices(null);
    return result;
  }

  @override
  Future<Uint8List> readCharacteristic(
    DiscoveredCharacteristic characteristic,
  ) {
    final result = _requests
        .begin<Uint8List>(_Request.read, key: characteristic.key)
        .future;
    _connected.readValueForCharacteristic(characteristic.cb);
    return result;
  }

  @override
  Future<void> writeCharacteristic(
    DiscoveredCharacteristic characteristic,
    Uint8List value, {
    required bool withResponse,
  }) async {
    final native = characteristic.cb;
    final data = value.toNSData();
    if (withResponse) {
      final result = _requests
          .begin<void>(_Request.write, key: characteristic.key)
          .future;
      _connected.writeValue(
        data,
        forCharacteristic: native,
        type: CBCharacteristicWriteType.CBCharacteristicWriteWithResponse,
      );
      return result;
    }
    while (!_connected.canSendWriteWithoutResponse) {
      BtLog.gatt.warning(
        () =>
            '$id: write buffer full; waiting for '
            'peripheralIsReadyToSendWriteWithoutResponse',
      );
      await (_readyToWrite = Completer()).future;
    }
    _connected.writeValue(
      data,
      forCharacteristic: native,
      type: CBCharacteristicWriteType.CBCharacteristicWriteWithoutResponse,
    );
  }

  /// iOS picks notification or indication itself, so [mode] only says
  /// whether to turn pushes on.
  @override
  Future<void> setNotifying(
    DiscoveredCharacteristic characteristic,
    NotifyMode? mode,
  ) {
    final result = _requests
        .begin<void>(_Request.notify, key: characteristic.key)
        .future;
    _connected.setNotifyValue(
      mode != null,
      forCharacteristic: characteristic.cb,
    );
    return result;
  }

  @override
  Future<Uint8List> readDescriptor(DiscoveredDescriptor descriptor) {
    final result = _requests.begin<Uint8List>(_Request.readDescriptor).future;
    _connected.readValueForDescriptor(descriptor.cb);
    return result;
  }

  @override
  Future<void> writeDescriptor(
    DiscoveredDescriptor descriptor,
    Uint8List value,
  ) {
    if (descriptor.uuid == BluetoothUuid.clientCharacteristicConfiguration) {
      throw const UnsupportedFeatureException(
        'writeClientCharacteristicConfiguration',
        'iOS manages this descriptor; use GattCharacteristic.subscribe()',
      );
    }
    final result = _requests.begin<void>(_Request.writeDescriptor).future;
    _connected.writeValue$1(value.toNSData(), forDescriptor: descriptor.cb);
    return result;
  }

  @override
  Future<int> readRssi() {
    final result = _requests.begin<int>(_Request.rssi).future;
    _connected.readRSSI();
    return result;
  }

  @override
  Future<int> requestMtu(int mtu) async => this.mtu;

  @override
  int maximumWriteLength({required bool withResponse}) =>
      peripheral.maximumWriteValueLengthForType(
        withResponse
            ? CBCharacteristicWriteType.CBCharacteristicWriteWithResponse
            : CBCharacteristicWriteType.CBCharacteristicWriteWithoutResponse,
      );

  @override
  Future<void> requestConnectionPriority(ConnectionPriority priority) =>
      throw const UnsupportedFeatureException(
        'connectionPriority',
        'iOS chooses connection parameters itself',
      );

  @override
  Future<PhyInfo> setPreferredPhy(Set<Phy> tx, Set<Phy> rx, PhyCoding coding) =>
      throw const UnsupportedFeatureException(
        'phy',
        'iOS chooses the PHY itself',
      );

  @override
  Future<PhyInfo> readPhy() =>
      throw const UnsupportedFeatureException('phy', 'iOS hides the PHY');

  @override
  Future<bool> clearGattCache() => throw const UnsupportedFeatureException(
    'gattCacheRefresh',
    'iOS keeps its GATT cache current itself',
  );

  @override
  Future<L2capChannelBackend> openL2capChannel(
    int psm, {
    required bool secure,
  }) {
    final result = _requests.begin<L2capChannelBackend>(_Request.l2cap).future;
    _connected.openL2CAPChannel(psm);
    return result;
  }

  /// iOS measures by Channel Sounding over this connection.
  @override
  Stream<DistanceMeasurement> measureDistance(
    DistanceMethod method,
    MeasurementRate rate,
  ) {
    if (method != DistanceMethod.channelSounding) {
      return Stream.error(
        const UnsupportedFeatureException(
          'rssiRanging',
          'iOS measures distance by Channel Sounding only',
        ),
      );
    }
    late final StreamController<DistanceMeasurement> controller;
    controller = StreamController(
      onListen: () {
        if (_state != BluetoothConnectionState.connected) {
          controller.addError(const DisconnectedException());
          unawaited(controller.close());
          return;
        }
        _distance = controller;
        peripheral.startChannelSoundingSession(
          CBChannelSoundingSessionConfiguration.alloc().initWithRole(
            CBChannelSoundingSessionConfigurationRole
                .CBChannelSoundingSessionConfigurationRoleInitiator,
          ),
        );
      },
      onCancel: () {
        if (!identical(_distance, controller)) return;
        _distance = null;
        if (_state == BluetoothConnectionState.connected) {
          _cancelledSessions++;
          peripheral.cancelChannelSoundingSession();
        }
      },
    );
    return controller.stream;
  }

  void _measured(
    CBChannelSoundingProcedureResults? results,
    objc.NSError? error,
  ) {
    final distance = _distance;
    if (distance == null || _cancelledSessions > 0) return;
    if (error != null) return _endDistance(_rangingError(error));
    if (results == null) return;
    distance.add(
      DistanceMeasurement(
        meters: results.distance,
        method: DistanceMethod.channelSounding,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _sessionCompleted(objc.NSError? error) {
    if (_cancelledSessions > 0) {
      _cancelledSessions--;
      return;
    }
    _endDistance(error == null ? null : _rangingError(error));
  }

  void _endDistance([BluetoothException? error]) {
    final distance = _distance;
    _distance = null;
    if (distance == null) return;
    if (error != null) distance.addError(error);
    unawaited(distance.close());
  }

  static RangingException _rangingError(objc.NSError error) => RangingException(
    'Channel Sounding failed: ${error.localizedDescription.toDartString()}',
    nativeCode: error.code,
    nativeError: error,
  );

  void _servicesDiscovered(objc.NSError? error) {
    if (error != null) return _fail(_Request.discover, error);
    _discovered = {
      for (final service in listOf(peripheral.services, CBService.as))
        keyOf(service): service,
    };
    if (_discovered.isEmpty) return _discoveryDone();
    _pendingIncludes = _discovered.length;
    for (final service in _discovered.values) {
      peripheral.discoverIncludedServices(null, forService: service);
    }
  }

  /// Included services not found yet, such as secondary services, join the
  /// discovery and have their own included services discovered.
  void _includedDiscovered(CBService service, objc.NSError? error) {
    if (error != null) return _fail(_Request.discover, error);
    for (final included in listOf(service.includedServices, CBService.as)) {
      if (_discovered.containsKey(keyOf(included))) continue;
      _discovered[keyOf(included)] = included;
      _pendingIncludes++;
      peripheral.discoverIncludedServices(null, forService: included);
    }
    if (--_pendingIncludes > 0) return;
    _pendingDiscoveries = _discovered.length;
    for (final service in _discovered.values) {
      peripheral.discoverCharacteristics(null, forService: service);
    }
  }

  void _characteristicsDiscovered(CBService service, objc.NSError? error) {
    if (error != null) return _fail(_Request.discover, error);
    final characteristics = _characteristics(service);
    _pendingDiscoveries += characteristics.length - 1;
    for (final characteristic in characteristics) {
      peripheral.discoverDescriptorsForCharacteristic(characteristic);
    }
    if (_pendingDiscoveries == 0) _discoveryDone();
  }

  void _descriptorsDiscovered(objc.NSError? error) {
    if (error != null) return _fail(_Request.discover, error);
    if (--_pendingDiscoveries == 0) _discoveryDone();
  }

  void _discoveryDone() => _requests.complete(_Request.discover, [
    for (final service in _discovered.values)
      DiscoveredService(
        uuidOf(service.UUID),
        service.isPrimary,
        keyOf(service),
        [
          for (final c in _characteristics(service))
            DiscoveredCharacteristic(uuidOf(c.UUID), c.properties, keyOf(c), [
              for (final d in listOf(c.descriptors, CBDescriptor.as))
                DiscoveredDescriptor(uuidOf(d.UUID), keyOf(d), IosHandle(d)),
            ], IosHandle(c)),
        ],
        IosHandle(service),
        included: [
          for (final included in listOf(service.includedServices, CBService.as))
            keyOf(included),
        ],
      ),
  ]);

  void _valueUpdated(CBCharacteristic characteristic, objc.NSError? error) {
    final key = keyOf(characteristic);
    if (error != null) {
      _requests.fail(_Request.read, errorOf(error, 'read'), key: key);
      return;
    }
    final value = bytesOf(characteristic.value);
    if (!_requests.complete(_Request.read, value, key: key)) {
      _notifications.add((key: key, value: value));
    }
  }

  void _finish(
    _Request request,
    objc.NSError? error,
    Object? Function()? value, {
    Object? key,
  }) {
    if (error != null) {
      _requests.fail(request, errorOf(error, request.name), key: key);
    } else {
      _requests.complete(request, value?.call(), key: key);
    }
  }

  void _fail(_Request request, objc.NSError error) =>
      _requests.fail(request, errorOf(error, request.name));

  void _disconnected(
    DisconnectCause cause,
    objc.NSError? nativeError,
    BluetoothException error,
  ) {
    _lastDisconnect = DisconnectReason(
      cause,
      nativeCode: nativeError?.code,
      at: DateTime.now(),
    );
    final failure = error is DisconnectedException
        ? DisconnectedException(error.message, _lastDisconnect)
        : error;
    _requests.failAny(failure);
    final ready = _readyToWrite;
    if (ready != null && !ready.isCompleted) ready.completeError(failure);
    _cancelledSessions = 0;
    _endDistance(failure);
    _setState(BluetoothConnectionState.disconnected);
  }

  void _setState(BluetoothConnectionState state) {
    if (_state == state) return;
    _state = state;
    _states.add(state);
  }

  List<CBCharacteristic> _characteristics(CBService service) =>
      listOf(service.characteristics, CBCharacteristic.as);

  static int? _cbErrorCode(objc.NSError? error) =>
      error != null &&
          error.domain.toDartString() == CBErrorDomain.toDartString()
      ? error.code
      : null;
}

/// Why a link went down, from the `CBError` code CoreBluetooth passed to
/// `centralManager:didDisconnectPeripheral:error:` (null when there was no
/// `CBErrorDomain` error) and the state the link was in.
DisconnectCause iosDisconnectCause(
  int? code, {
  required BluetoothConnectionState from,
}) => switch (from) {
  BluetoothConnectionState.connecting => DisconnectCause.failedToConnect,
  BluetoothConnectionState.disconnecting => DisconnectCause.requested,
  _ => switch (CBError.values.where((e) => e.value == code).firstOrNull) {
    CBError.CBErrorConnectionTimeout => DisconnectCause.linkLoss,
    CBError.CBErrorPeripheralDisconnected => DisconnectCause.remote,
    CBError.CBErrorConnectionFailed => DisconnectCause.failedToConnect,
    _ => DisconnectCause.unknown,
  },
};

extension on DiscoveredCharacteristic {
  CBCharacteristic get cb => native!.ios!;
}

extension on DiscoveredDescriptor {
  CBDescriptor get cb => native!.ios!;
}
