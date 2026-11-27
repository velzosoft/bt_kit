import 'dart:async';
import 'dart:typed_data';

import 'package:jni/jni.dart';

import '../../central/native_types.dart';
import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../core/native_handle.dart';
import '../../models/attribute_permission.dart';
import '../../models/connection_priority.dart';
import '../../native/android/bindings.dart';
import '../../peripheral_role/local_gatt.dart';
import '../peripheral_role_backend.dart';
import '../request_slot.dart';
import 'jni_conversions.dart';

/// A GATT server on `BluetoothGattServer`.
///
/// Platform quirks handled here:
/// * Android does not track subscriptions: every notifying characteristic
///   gets a Client Characteristic Configuration descriptor, and its writes
///   are tracked per central.
/// * Services must be added one at a time, each after `onServiceAdded`.
/// * Prepared writes arrive in pieces and are assembled at execution.
/// * Only one notification per central may be in flight; the next waits
///   for `onNotificationSent`.
final class AndroidGattServer implements ServerBackend {
  AndroidGattServer._();

  static Future<AndroidGattServer> open(
    Context context,
    BluetoothManager manager,
  ) async {
    final server = AndroidGattServer._();
    server._server =
        guardJni(
          'Opening the GATT server',
          () => manager.openGattServer(context, server._callback),
        ) ??
        (throw const NativeOperationException(
          'Android could not open a GATT server; is Bluetooth on?',
        ));
    return server;
  }

  static const _busyRetries = 5;
  static const _addService = 'addService';

  late final BluetoothGattServer _server;
  final _events = StreamController<ServerEvent>();
  final _requests = RequestSlot();
  final _centrals = <String, AndroidRemoteCentral>{};
  final _characteristics = <int, BluetoothGattCharacteristic>{};
  final _subscriptions = <String, Map<int, int>>{};
  final _prepared = <String, List<AttributeWrite>>{};
  final _notificationsSent = <String, Completer<int>>{};

  late final BluetoothGattServerCallback
  _callback = BluetoothGattServerCallback.implement(
    onConnectionStateChange: (device, status, newState) =>
        _connectionChanged(device!, newState),
    onServiceAdded: (status, service) => status == BluetoothGatt.GATT_SUCCESS
        ? _requests.complete(_addService, null)
        : _requests.fail(
            _addService,
            NativeOperationException(
              'Android rejected the service',
              nativeCode: status,
            ),
          ),
    onCharacteristicReadRequest: (device, requestId, offset, characteristic) =>
        _read(device!, requestId, offset, characteristic!.instanceId),
    onCharacteristicWriteRequest:
        (device, requestId, characteristic, prepared, needed, offset, value) =>
            _write(
              device!,
              requestId,
              characteristic!.instanceId,
              offset,
              takeBytes(value),
              prepared: prepared,
              responseNeeded: needed,
            ),
    onDescriptorReadRequest: (device, requestId, offset, descriptor) =>
        _isCccd(descriptor!)
        ? _readCccd(device!, requestId, offset, descriptor)
        : _read(device!, requestId, offset, _descriptorKey(descriptor)),
    onDescriptorWriteRequest:
        (device, requestId, descriptor, prepared, needed, offset, value) =>
            _isCccd(descriptor!)
            ? _writeCccd(
                device!,
                requestId,
                descriptor,
                takeBytes(value),
                needed,
              )
            : _write(
                device!,
                requestId,
                _descriptorKey(descriptor),
                offset,
                takeBytes(value),
                prepared: prepared,
                responseNeeded: needed,
              ),
    onExecuteWrite: (device, requestId, execute) =>
        _execute(device!, requestId, execute: execute),
    onNotificationSent: (device, status) =>
        _notificationsSent.remove(_central(device!).id)?.complete(status),
    onMtuChanged: (device, mtu) => _central(device!).mtu = mtu,
  );

  @override
  ServerHandle get native => AndroidHandle(_server);

  @override
  Future<void> requestConnectionPriority(
    Central central,
    ConnectionPriority priority,
  ) => throw const UnsupportedFeatureException(
    'serverConnectionPriority',
    'Android GATT servers cannot ask for a connection priority',
  );

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  Future<AddedService> addService(
    LocalService service,
    List<AddedService> included,
  ) async {
    final native = BluetoothGattService(
      javaUuid(service.uuid),
      service.isPrimary
          ? BluetoothGattService.SERVICE_TYPE_PRIMARY
          : BluetoothGattService.SERVICE_TYPE_SECONDARY,
    );
    for (final other in included) {
      native.addService(other.native!.android);
    }
    final characteristics = <LocalCharacteristic, BluetoothGattCharacteristic>{
      for (final characteristic in service.characteristics)
        characteristic: _characteristic(characteristic),
    };
    for (final characteristic in characteristics.values) {
      native.addCharacteristic(characteristic);
    }
    final added = _requests.begin<void>(_addService).future;
    if (!guardJni('Adding a service', () => _server.addService(native))) {
      _requests.fail(
        _addService,
        const NativeOperationException('Android rejected the service'),
      );
    }
    await added;

    final keys = <LocalAttribute, Object>{};
    for (final MapEntry(key: local, value: characteristic)
        in characteristics.entries) {
      final key = characteristic.instanceId;
      _characteristics[key] = characteristic;
      keys[local] = key;
      for (final descriptor in local.descriptors) {
        keys[descriptor] = '$key/${descriptor.uuid}';
      }
    }
    return AddedService(
      service,
      keys,
      native: AndroidHandle(native),
      natives: {
        for (final MapEntry(:key, :value) in characteristics.entries)
          key: AndroidHandle(value),
      },
    );
  }

  @override
  Future<void> removeService(AddedService service) async {
    for (final key in service.keys.values.whereType<int>()) {
      _characteristics.remove(key);
    }
    guardJni(
      'Removing a service',
      () => _server.removeService(service.native?.android),
    );
  }

  @override
  Future<void> notify(Object key, Uint8List value, Central central) async {
    final device = (central as AndroidRemoteCentral).device;
    final characteristic = _characteristics[key as int];
    if (characteristic == null) {
      throw const NativeOperationException('The characteristic was removed');
    }
    final configuration = _subscriptions[central.id]?[key] ?? 0;
    final indicate = configuration & 0x01 == 0 && configuration & 0x02 != 0;
    final sent = _notificationsSent[central.id] = Completer<int>();
    final bytes = JByteArray.of(value);
    try {
      int send() => guardJni(
        'Sending a notification',
        () => _server.notifyCharacteristicChanged(
          device,
          characteristic,
          indicate,
          bytes,
        ),
      );
      var status = send();
      for (
        var retry = 1;
        status == BluetoothStatusCodes.ERROR_GATT_WRITE_REQUEST_BUSY &&
            retry <= _busyRetries;
        retry++
      ) {
        BtLog.server.warning(
          () =>
              '${central.id}: notification refused while the stack is '
              'busy; retry $retry of $_busyRetries',
        );
        await Future<void>.delayed(Duration(milliseconds: 10 * retry));
        status = send();
      }
      if (status != BluetoothStatusCodes.SUCCESS) {
        _notificationsSent.remove(central.id);
        throw NativeOperationException(
          'Android refused the notification',
          nativeCode: status,
        );
      }
    } finally {
      bytes.release();
    }
    final status = await sent.future;
    if (status != BluetoothGatt.GATT_SUCCESS) {
      throw GattException(
        GattError.fromCode(status),
        'notify',
        nativeCode: status,
      );
    }
  }

  @override
  Future<void> close() async {
    guardJni('Closing the GATT server', _server.close);
    _requests.failAny(const DisconnectedException('The server closed'));
    for (final sent in _notificationsSent.values) {
      sent.complete(BluetoothGatt.GATT_FAILURE);
    }
    await _events.close();
  }

  BluetoothGattCharacteristic _characteristic(LocalCharacteristic local) {
    final characteristic = BluetoothGattCharacteristic(
      javaUuid(local.uuid),
      local.properties.bits,
      _permissions(local.permissions),
    );
    for (final descriptor in local.descriptors) {
      characteristic.addDescriptor(
        BluetoothGattDescriptor(
          javaUuid(descriptor.uuid),
          _permissions(descriptor.permissions),
        ),
      );
    }
    if (local.canNotify) {
      characteristic.addDescriptor(
        BluetoothGattDescriptor(
          javaUuid(BluetoothUuid.clientCharacteristicConfiguration),
          BluetoothGattDescriptor.PERMISSION_READ |
              BluetoothGattDescriptor.PERMISSION_WRITE,
        ),
      );
    }
    return characteristic;
  }

  AndroidRemoteCentral _central(BluetoothDevice device) {
    final id = takeString(device.address)!;
    return _centrals[id] ??= AndroidRemoteCentral(device, id);
  }

  void _connectionChanged(BluetoothDevice device, int newState) {
    final central = _central(device);
    if (newState == BluetoothProfile.STATE_CONNECTED) {
      _events.add(CentralConnected(central));
    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
      _centrals.remove(central.id);
      _subscriptions.remove(central.id);
      _prepared.remove(central.id);
      _notificationsSent
          .remove(central.id)
          ?.complete(BluetoothGatt.GATT_FAILURE);
      _events.add(CentralDisconnected(central));
    }
  }

  void _read(BluetoothDevice device, int requestId, int offset, Object key) =>
      _events.add(
        ReadRequested(
          _central(device),
          key,
          offset,
          (error, [value]) => _respond(device, requestId, error, offset, value),
        ),
      );

  void _write(
    BluetoothDevice device,
    int requestId,
    Object key,
    int offset,
    Uint8List value, {
    required bool prepared,
    required bool responseNeeded,
  }) {
    final central = _central(device);
    if (prepared) {
      _prepared.putIfAbsent(central.id, () => []).add((
        key: key,
        offset: offset,
        value: value,
      ));
      if (responseNeeded) _respond(device, requestId, null, offset, value);
      return;
    }
    _events.add(
      WriteRequested(
        central,
        [(key: key, offset: offset, value: value)],
        responseNeeded
            ? (error, [_]) => _respond(device, requestId, error, offset)
            : null,
      ),
    );
  }

  void _execute(
    BluetoothDevice device,
    int requestId, {
    required bool execute,
  }) {
    final central = _central(device);
    final queued = _prepared.remove(central.id) ?? const [];
    if (!execute || queued.isEmpty) {
      return _respond(device, requestId, null, 0);
    }
    _events.add(
      WriteRequested(
        central,
        assembleWrites(queued),
        (error, [_]) => _respond(device, requestId, error, 0),
      ),
    );
  }

  void _readCccd(
    BluetoothDevice device,
    int requestId,
    int offset,
    BluetoothGattDescriptor descriptor,
  ) {
    final key = descriptor.characteristic?.instanceId;
    final configuration = _subscriptions[_central(device).id]?[key] ?? 0;
    final value = Uint8List.fromList([
      configuration & 0xff,
      configuration >> 8,
    ]);
    if (offset > value.length) {
      return _respond(device, requestId, GattError.invalidOffset, offset);
    }
    _respond(device, requestId, null, offset, value.sublist(offset));
  }

  void _writeCccd(
    BluetoothDevice device,
    int requestId,
    BluetoothGattDescriptor descriptor,
    Uint8List value,
    bool responseNeeded,
  ) {
    final key = descriptor.characteristic?.instanceId;
    if (key == null || value.isEmpty) {
      if (responseNeeded) {
        _respond(device, requestId, GattError.invalidAttributeValueLength, 0);
      }
      return;
    }
    final central = _central(device);
    final configuration = value[0] | (value.length > 1 ? value[1] << 8 : 0);
    final subscriptions = _subscriptions.putIfAbsent(central.id, () => {});
    final was = subscriptions[key] ?? 0;
    subscriptions[key] = configuration;
    if (responseNeeded) _respond(device, requestId, null, 0, value);
    if ((was == 0) != (configuration == 0)) {
      _events.add(
        SubscriptionChanged(central, key, subscribed: configuration != 0),
      );
    }
  }

  void _respond(
    BluetoothDevice device,
    int requestId,
    GattError? error,
    int offset, [
    Uint8List? value,
  ]) {
    final bytes = value == null ? null : JByteArray.of(value);
    guardJni(
      'Responding to a request',
      () => _server.sendResponse(
        device,
        requestId,
        error?.code ?? BluetoothGatt.GATT_SUCCESS,
        offset,
        bytes,
      ),
    );
    bytes?.release();
  }

  static bool _isCccd(BluetoothGattDescriptor descriptor) =>
      takeUuid(descriptor.uuid) ==
      BluetoothUuid.clientCharacteristicConfiguration;

  static String _descriptorKey(BluetoothGattDescriptor descriptor) =>
      '${descriptor.characteristic?.instanceId}/${takeUuid(descriptor.uuid)}';

  static int _permissions(Set<AttributePermission> permissions) {
    const flags = {
      AttributePermission.read: BluetoothGattCharacteristic.PERMISSION_READ,
      AttributePermission.readEncrypted:
          BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED,
      AttributePermission.write: BluetoothGattCharacteristic.PERMISSION_WRITE,
      AttributePermission.writeEncrypted:
          BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED,
    };
    return permissions.fold(0, (bits, p) => bits | flags[p]!);
  }
}

/// A central connected to this device's GATT server.
final class AndroidRemoteCentral implements Central {
  AndroidRemoteCentral(this.device, this.id);

  final BluetoothDevice device;

  @override
  final String id;

  /// The ATT MTU, updated by `onMtuChanged`. 23 until negotiated.
  int mtu = 23;

  @override
  int get maximumUpdateLength => mtu - 3;

  @override
  CentralHandle get native => AndroidHandle(device);
}
