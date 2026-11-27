import 'dart:async';
import 'dart:typed_data';

import 'package:jni/jni.dart';

import '../../central/native_types.dart';
import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../core/native_handle.dart';
import '../../models/adapter_state.dart';
import '../../models/connection_priority.dart';
import '../../models/bluetooth_connection_state.dart';
import '../../models/disconnect_reason.dart';
import '../../models/distance.dart';
import '../../models/notify_mode.dart';
import '../../models/phy.dart';
import '../../native/android/bindings.dart';
import '../bond_backend.dart';
import '../central_backend.dart';
import '../channel_backend.dart';
import '../request_slot.dart';
import 'android_bonds.dart';
import 'android_central.dart';
import 'android_ranging.dart';
import 'android_sockets.dart';
import 'jni_conversions.dart';

enum _Request {
  connect,
  discover,
  read,
  write,
  readDescriptor,
  writeDescriptor,
  rssi,
  mtu,
  phyUpdate,
  phyRead,
}

/// A GATT client for one device, built on `BluetoothGatt`.
///
/// Platform quirks handled here:
/// * Android closes nothing by itself: every `BluetoothGatt` must be closed
///   after it disconnects, or the app runs out of client slots.
/// * `disconnect()` sometimes never reports the disconnection, so the client
///   is closed after a grace period.
/// * Writes are refused with `ERROR_GATT_WRITE_REQUEST_BUSY` while the stack
///   is still busy with the previous one; they are retried briefly.
/// * Android 14 and later negotiate an MTU of 517 on their own and report it
///   through `onMtuChanged` without a request.
/// * `setPreferredPhy` may not call back when the PHY does not change, so
///   the PHY is read after a short wait.
/// * The GATT cache can only be cleared through `BluetoothGatt.refresh()`,
///   which the SDK hides; it is called through JNI and may be refused.
final class AndroidGattClient implements PeripheralBackend {
  AndroidGattClient(this._central, this._device, this.id);

  static const _disconnectGrace = Duration(seconds: 5);
  static const _phyUpdateWait = Duration(seconds: 3);
  static const _busyRetries = 5;
  static const _defaultMtu = 23;

  final AndroidCentral _central;
  final BluetoothDevice _device;
  final _requests = RequestSlot();
  final _states = StreamController<BluetoothConnectionState>.broadcast();
  final _notifications = StreamController<ValueNotification>.broadcast();
  final _updates = StreamController<LinkUpdate>.broadcast();

  BluetoothGatt? _gatt;
  var _state = BluetoothConnectionState.disconnected;
  var _mtu = _defaultMtu;
  DisconnectReason? _lastDisconnect;
  Future<void>? _disconnecting;
  var _attempt = 0;

  late final BluetoothGattCallback _callback = BluetoothGattCallback.implement(
    onConnectionStateChange: (gatt, status, newState) {
      gatt?.release();
      _onConnectionStateChange(status, newState);
    },
    onServicesDiscovered: (gatt, status) =>
        _finish(_Request.discover, status, () => _services(gatt)),
    onServiceChanged: (gatt) {
      gatt?.release();
      _updates.add(const ServicesUpdate());
    },
    onCharacteristicRead: (gatt, characteristic, value, status) => _finish(
      _Request.read,
      status,
      () => takeBytes(value),
      key: _key(characteristic),
    ),
    onCharacteristicWrite: (gatt, characteristic, status) =>
        _finish(_Request.write, status, () => null, key: _key(characteristic)),
    onCharacteristicChanged: (gatt, characteristic, value) {
      final key = _key(characteristic);
      if (key != null) {
        _notifications.add((key: key, value: takeBytes(value)));
      }
    },
    onDescriptorRead: (gatt, descriptor, status, value) =>
        _finish(_Request.readDescriptor, status, () => takeBytes(value)),
    onDescriptorWrite: (gatt, descriptor, status) =>
        _finish(_Request.writeDescriptor, status, () => null),
    onReadRemoteRssi: (gatt, rssi, status) =>
        _finish(_Request.rssi, status, () => rssi),
    onMtuChanged: (gatt, mtu, status) {
      if (status == BluetoothGatt.GATT_SUCCESS && mtu != _mtu) {
        _mtu = mtu;
        _updates.add(MtuUpdate(mtu));
      }
      _finish(_Request.mtu, status, () => _mtu);
    },
    onPhyUpdate: (gatt, tx, rx, status) {
      final phy = PhyInfo(tx: _phy(tx), rx: _phy(rx));
      if (status == BluetoothGatt.GATT_SUCCESS) _updates.add(PhyUpdate(phy));
      _finish(_Request.phyUpdate, status, () => phy);
    },
    onPhyRead: (gatt, tx, rx, status) => _finish(
      _Request.phyRead,
      status,
      () => PhyInfo(tx: _phy(tx), rx: _phy(rx)),
    ),
  );

  @override
  final String id;

  @override
  String? get name =>
      guardJni('Reading the device name', () => takeString(_device.name));

  @override
  PeripheralHandle get native =>
      AndroidHandle(AndroidPeripheral(_device, () => _gatt));

  @override
  BluetoothConnectionState get connectionState => _state;

  @override
  Stream<BluetoothConnectionState> get connectionStates => _states.stream;

  @override
  DisconnectReason? get lastDisconnect => _lastDisconnect;

  @override
  late final BondBackend bond = AndroidBond(
    _central.bonds,
    _central.companion,
    _device,
    id,
  );

  @override
  Stream<ValueNotification> get notifications => _notifications.stream;

  @override
  Stream<LinkUpdate> get updates => _updates.stream;

  @override
  int get mtu => _mtu;

  BluetoothGatt get _connected =>
      _state == BluetoothConnectionState.connected && _gatt != null
      ? _gatt!
      : throw const DisconnectedException();

  @override
  Future<void> connect({required bool autoConnect}) async {
    final attempt = ++_attempt;
    await _disconnecting;
    if (attempt != _attempt) throw const OperationCancelledException();
    _close();
    _setState(BluetoothConnectionState.connecting);
    final connected = _requests.begin<void>(_Request.connect).future;
    _gatt = guardJni(
      'Connecting',
      () => _device.connectGatt$3(
        _central.context,
        autoConnect,
        _callback,
        BluetoothDevice.TRANSPORT_LE,
        BluetoothDevice.PHY_LE_1M_MASK,
      ),
    );
    if (_gatt == null) {
      _disconnected(
        DisconnectCause.failedToConnect,
        null,
        const ConnectionException('connectGatt returned null'),
      );
    }
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
    final gatt = _gatt;
    if (gatt == null || _state == BluetoothConnectionState.disconnected) return;
    if (_state == BluetoothConnectionState.connecting) {
      _disconnected(
        DisconnectCause.requested,
        null,
        const OperationCancelledException('Disconnected'),
      );
      return;
    }
    _setState(BluetoothConnectionState.disconnecting);
    final disconnected = _states.stream.firstWhere(
      (s) => s == BluetoothConnectionState.disconnected,
    );
    gatt.disconnect();
    await disconnected.timeout(
      _disconnectGrace,
      onTimeout: () {
        BtLog.gatt.warning(
          () =>
              '$id: Android did not report the disconnection; closing '
              'the client after ${millis(_disconnectGrace)}',
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

  @override
  Future<List<DiscoveredService>> discoverServices() =>
      _send(_Request.discover, () => _connected.discoverServices());

  @override
  Future<Uint8List> readCharacteristic(
    DiscoveredCharacteristic characteristic,
  ) {
    final native = characteristic.java;
    return _send(
      _Request.read,
      () => _connected.readCharacteristic(native),
      key: characteristic.key,
    );
  }

  @override
  Future<void> writeCharacteristic(
    DiscoveredCharacteristic characteristic,
    Uint8List value, {
    required bool withResponse,
  }) {
    final native = characteristic.java;
    final type = withResponse
        ? BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        : BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE;
    return _write(
      _Request.write,
      (bytes) => _connected.writeCharacteristic(native, bytes, type),
      value,
      key: characteristic.key,
    );
  }

  @override
  Future<void> setNotifying(
    DiscoveredCharacteristic characteristic,
    NotifyMode? mode,
  ) async {
    final native = characteristic.java;
    final accepted = guardJni(
      'Configuring notifications',
      () => _connected.setCharacteristicNotification(native, mode != null),
    );
    if (!accepted) {
      throw const NativeOperationException(
        'setCharacteristicNotification was rejected',
      );
    }
    final cccd = native.getDescriptor(
      javaUuid(BluetoothUuid.clientCharacteristicConfiguration),
    );
    if (cccd == null) return;
    final value = switch (mode) {
      null => BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE,
      NotifyMode.indication => BluetoothGattDescriptor.ENABLE_INDICATION_VALUE,
      _ => BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
    };
    await _writeDescriptor(cccd, takeBytes(value));
  }

  @override
  Future<Uint8List> readDescriptor(DiscoveredDescriptor descriptor) => _send(
    _Request.readDescriptor,
    () => _connected.readDescriptor(descriptor.java),
  );

  @override
  Future<void> writeDescriptor(
    DiscoveredDescriptor descriptor,
    Uint8List value,
  ) => _writeDescriptor(descriptor.java, value);

  Future<void> _writeDescriptor(
    BluetoothGattDescriptor descriptor,
    Uint8List value,
  ) => _write(
    _Request.writeDescriptor,
    (bytes) => _connected.writeDescriptor(descriptor, bytes),
    value,
  );

  @override
  Future<int> readRssi() =>
      _send(_Request.rssi, () => _connected.readRemoteRssi());

  @override
  Future<int> requestMtu(int mtu) =>
      _send(_Request.mtu, () => _connected.requestMtu(mtu));

  @override
  int maximumWriteLength({required bool withResponse}) =>
      withResponse ? 512 : _mtu - 3;

  @override
  Future<void> requestConnectionPriority(ConnectionPriority priority) async {
    final accepted = guardJni(
      'Requesting a connection priority',
      () => _connected.requestConnectionPriority(switch (priority) {
        ConnectionPriority.balanced =>
          BluetoothGatt.CONNECTION_PRIORITY_BALANCED,
        ConnectionPriority.high => BluetoothGatt.CONNECTION_PRIORITY_HIGH,
        ConnectionPriority.lowPower =>
          BluetoothGatt.CONNECTION_PRIORITY_LOW_POWER,
      }),
    );
    if (!accepted) {
      throw const NativeOperationException(
        'Android rejected the connection priority request',
      );
    }
  }

  @override
  Future<PhyInfo> setPreferredPhy(Set<Phy> tx, Set<Phy> rx, PhyCoding coding) {
    final update = _send<PhyInfo>(_Request.phyUpdate, () {
      _connected.setPreferredPhy(_phyMask(tx), _phyMask(rx), switch (coding) {
        PhyCoding.none => BluetoothDevice.PHY_OPTION_NO_PREFERRED,
        PhyCoding.s2 => BluetoothDevice.PHY_OPTION_S2,
        PhyCoding.s8 => BluetoothDevice.PHY_OPTION_S8,
      });
      return true;
    });
    return update.timeout(
      _phyUpdateWait,
      onTimeout: () {
        BtLog.gatt.warning(
          () =>
              '$id: no onPhyUpdate after ${millis(_phyUpdateWait)}; '
              'reading the PHY instead',
        );
        return readPhy();
      },
    );
  }

  @override
  Future<PhyInfo> readPhy() => _send(_Request.phyRead, () {
    _connected.readPhy();
    return true;
  });

  @override
  Future<bool> clearGattCache() async {
    final gatt = _connected;
    try {
      return guardJni<bool>(
        'BluetoothGatt.refresh()',
        () => _refresh.call(gatt, jboolean.type, const []),
      );
    } on NativeOperationException catch (e) {
      BtLog.gatt.warning(() => '$id: Android refused to clear the cache: $e');
      return false;
    }
  }

  static final _refresh = BluetoothGatt.type.jClass.instanceMethodId(
    'refresh',
    '()Z',
  );

  @override
  Future<L2capChannelBackend> openL2capChannel(
    int psm, {
    required bool secure,
  }) => AndroidL2capChannel.connect(_device, id, psm, secure: secure);

  /// Ranging talks to the device by address; it needs a bond, not this
  /// client's connection.
  @override
  Stream<DistanceMeasurement> measureDistance(
    DistanceMethod method,
    MeasurementRate rate,
  ) => androidDistance(_central.context, id, method, rate);

  Future<T> _send<T>(_Request request, bool Function() send, {Object? key}) {
    final pending = _requests.begin<T>(request, key: key);
    try {
      if (!guardJni(request.name, send)) pending.fail(_rejected(request));
    } on BluetoothException catch (e) {
      pending.fail(e);
    }
    return pending.future;
  }

  Future<void> _write(
    _Request request,
    int Function(JByteArray bytes) send,
    Uint8List value, {
    Object? key,
  }) {
    final pending = _requests.begin<void>(request, key: key);
    unawaited(_sendWrite(pending, request, send, value));
    return pending.future;
  }

  /// Retries while the stack is busy with the previous write, for as long
  /// as [pending] has not been settled some other way.
  Future<void> _sendWrite(
    PendingRequest<void> pending,
    _Request request,
    int Function(JByteArray bytes) send,
    Uint8List value,
  ) async {
    final bytes = JByteArray.of(value);
    try {
      var status = guardJni(request.name, () => send(bytes));
      for (
        var retry = 1;
        status == BluetoothStatusCodes.ERROR_GATT_WRITE_REQUEST_BUSY &&
            retry <= _busyRetries;
        retry++
      ) {
        BtLog.gatt.warning(
          () =>
              '$id: ${request.name} refused while the stack is busy; '
              'retry $retry of $_busyRetries',
        );
        await Future<void>.delayed(Duration(milliseconds: 10 * retry));
        if (!pending.isPending) return;
        status = guardJni(request.name, () => send(bytes));
      }
      if (status != BluetoothStatusCodes.SUCCESS) {
        pending.fail(_rejected(request, status));
      }
    } on BluetoothException catch (e) {
      pending.fail(e);
    } finally {
      bytes.release();
    }
  }

  static NativeOperationException _rejected(_Request request, [int? status]) =>
      NativeOperationException(
        'Android rejected the ${request.name} request',
        nativeCode: status,
      );

  void _finish(
    _Request request,
    int status,
    Object? Function() value, {
    Object? key,
  }) {
    if (status == BluetoothGatt.GATT_SUCCESS) {
      _requests.complete(request, value(), key: key);
    } else {
      _requests.fail(
        request,
        GattException(_gattError(status), request.name, nativeCode: status),
        key: key,
      );
    }
  }

  void _onConnectionStateChange(int status, int newState) {
    if (newState == BluetoothProfile.STATE_CONNECTED &&
        status == BluetoothGatt.GATT_SUCCESS) {
      _setState(BluetoothConnectionState.connected);
      _requests.complete(_Request.connect, null);
    } else if (_state != BluetoothConnectionState.disconnected &&
        (newState == BluetoothProfile.STATE_DISCONNECTED ||
            status != BluetoothGatt.GATT_SUCCESS)) {
      final cause = androidDisconnectCause(
        status,
        from: _state,
        adapterOn: _central.adapterState == AdapterState.poweredOn,
      );
      _disconnected(
        cause,
        status,
        cause == DisconnectCause.failedToConnect
            ? ConnectionException('Connection failed', nativeCode: status)
            : DisconnectedException('Disconnected (status $status)'),
      );
    }
  }

  void _disconnected(
    DisconnectCause cause,
    int? status,
    BluetoothException error,
  ) {
    _close();
    _lastDisconnect = DisconnectReason(
      cause,
      nativeCode: status,
      at: DateTime.now(),
    );
    _requests.failAny(
      error is DisconnectedException
          ? DisconnectedException(error.message, _lastDisconnect)
          : error,
    );
    _mtu = _defaultMtu;
    _setState(BluetoothConnectionState.disconnected);
  }

  void _close() {
    final gatt = _gatt;
    _gatt = null;
    if (gatt == null) return;
    guardJni('Closing the GATT client', gatt.close);
    gatt.release();
  }

  void _setState(BluetoothConnectionState state) {
    if (_state == state) return;
    _state = state;
    _states.add(state);
  }

  List<DiscoveredService> _services(BluetoothGatt? gatt) {
    final services =
        gatt?.services?.asDart() ?? const <BluetoothGattService?>[];
    gatt?.release();
    return [for (final service in services.nonNulls) _service(service)];
  }

  /// Android lists secondary services too, and points included services at
  /// the listed objects.
  DiscoveredService _service(BluetoothGattService service) => DiscoveredService(
    takeUuid(service.uuid),
    service.type$1 == BluetoothGattService.SERVICE_TYPE_PRIMARY,
    service.instanceId,
    [
      for (final c
          in service.characteristics?.asDart().nonNulls ??
              const <BluetoothGattCharacteristic>[])
        _characteristic(c),
    ],
    AndroidHandle(service),
    included: [
      for (final included
          in service.includedServices?.asDart().nonNulls ??
              const <BluetoothGattService>[])
        included.instanceId,
    ],
  );

  DiscoveredCharacteristic _characteristic(BluetoothGattCharacteristic c) {
    final key = c.instanceId;
    return DiscoveredCharacteristic(takeUuid(c.uuid), c.properties, key, [
      for (final d
          in c.descriptors?.asDart().nonNulls ??
              const <BluetoothGattDescriptor>[])
        _descriptor(key, d),
    ], AndroidHandle(c));
  }

  static DiscoveredDescriptor _descriptor(
    int characteristic,
    BluetoothGattDescriptor descriptor,
  ) {
    final uuid = takeUuid(descriptor.uuid);
    return DiscoveredDescriptor(uuid, (
      characteristic,
      uuid,
    ), AndroidHandle(descriptor));
  }

  static int? _key(BluetoothGattCharacteristic? characteristic) {
    final key = characteristic?.instanceId;
    characteristic?.release();
    return key;
  }

  static int _phyMask(Set<Phy> phys) => phys.fold(
    0,
    (mask, phy) =>
        mask |
        switch (phy) {
          Phy.le1M => BluetoothDevice.PHY_LE_1M_MASK,
          Phy.le2M => BluetoothDevice.PHY_LE_2M_MASK,
          Phy.leCoded => BluetoothDevice.PHY_LE_CODED_MASK,
        },
  );

  static Phy _phy(int phy) => switch (phy) {
    BluetoothDevice.PHY_LE_2M => Phy.le2M,
    BluetoothDevice.PHY_LE_CODED => Phy.leCoded,
    _ => Phy.le1M,
  };

  /// Android reports ATT errors as GATT status codes, plus a few of its own
  /// such as `GATT_ERROR` (133) for unspecified link failures.
  static GattError _gattError(int status) => GattError.fromCode(status);
}

/// Why a link went down, from the status of `onConnectionStateChange` and
/// the state the link was in.
///
/// The statuses are HCI reasons that Android does not publish as constants:
/// 8 is a supervision timeout, 19 the peer ending the connection, 34 an LL
/// response timeout, 62 a connection that could not be established and 147
/// a connection attempt that timed out.
DisconnectCause androidDisconnectCause(
  int status, {
  required BluetoothConnectionState from,
  required bool adapterOn,
}) {
  if (!adapterOn) return DisconnectCause.adapterOff;
  return switch (from) {
    BluetoothConnectionState.connecting => DisconnectCause.failedToConnect,
    BluetoothConnectionState.disconnecting => DisconnectCause.requested,
    _ => switch (status) {
      8 || 34 => DisconnectCause.linkLoss,
      19 => DisconnectCause.remote,
      62 || 147 => DisconnectCause.failedToConnect,
      _ => DisconnectCause.unknown,
    },
  };
}

extension on DiscoveredCharacteristic {
  BluetoothGattCharacteristic get java => native!.android!;
}

extension on DiscoveredDescriptor {
  BluetoothGattDescriptor get java => native!.android!;
}
