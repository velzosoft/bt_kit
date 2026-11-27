import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:objective_c/objective_c.dart' as objc;

import '../../central/native_types.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../core/native_handle.dart';
import '../../models/attribute_permission.dart';
import '../../models/connection_priority.dart';
import '../../native/ios/bindings.dart';
import '../../peripheral_role/local_gatt.dart';
import '../peripheral_role_backend.dart';
import '../request_slot.dart';
import 'ios_peripheral_role.dart';
import 'objc_conversions.dart';

/// A GATT server on `CBPeripheralManager`.
///
/// Platform quirks handled here:
/// * Characteristics are created without a cached value, so every read
///   reaches Dart and values can change at any time.
/// * Descriptors are limited to fixed User Description and Presentation
///   Format values; CoreBluetooth manages the CCCD and subscriptions.
/// * A long write arrives as several requests in one callback; only the
///   first one is answered.
/// * `updateValue` refuses values while the transmit queue is full; it is
///   retried after `peripheralManagerIsReadyToUpdateSubscribers`.
/// * There are no connection events: a central appears with its first
///   request or subscription.
final class IosGattServer implements ServerBackend {
  IosGattServer(this._role);

  static const _addService = 'addService';

  final IosPeripheralRole _role;
  final _events = StreamController<ServerEvent>();
  final _requests = RequestSlot();
  final _centrals = <String, IosRemoteCentral>{};
  final _characteristics = <int, CBMutableCharacteristic>{};
  Completer<void>? _ready;
  var _closed = false;

  CBPeripheralManager get _manager => _role.manager;

  @override
  ServerHandle get native => IosHandle(_manager);

  @override
  Stream<ServerEvent> get events => _events.stream;

  @override
  Future<AddedService> addService(
    LocalService service,
    List<AddedService> included,
  ) async {
    if (_role.takeRestored(service) case (final native, final restored)) {
      BtLog.server.info(() => 'Adopted the restored service ${service.uuid}');
      return _added(service, native, {
        for (final (i, local) in service.characteristics.indexed)
          local: restored[i],
      });
    }
    final characteristics = {
      for (final local in service.characteristics)
        local: _characteristic(local),
    };
    final native = CBMutableService.alloc().initWithType(
      cbUuid(service.uuid),
      primary: service.isPrimary,
    )..characteristics$1 = objc.NSArray.of(characteristics.values);
    if (included.isNotEmpty) {
      native.includedServices$1 = objc.NSArray.of([
        for (final other in included) other.native!.ios!,
      ]);
    }
    final added = _requests.begin<void>(_addService).future;
    _manager.addService(native);
    await added;
    return _added(service, native, characteristics);
  }

  AddedService _added(
    LocalService service,
    CBMutableService native,
    Map<LocalCharacteristic, CBMutableCharacteristic> characteristics,
  ) {
    final keys = <LocalAttribute, Object>{};
    for (final MapEntry(key: local, value: characteristic)
        in characteristics.entries) {
      final key = keyOf(characteristic);
      _characteristics[key] = characteristic;
      keys[local] = key;
    }
    return AddedService(
      service,
      keys,
      native: IosHandle(native),
      natives: {
        for (final MapEntry(:key, :value) in characteristics.entries)
          key: IosHandle(value),
      },
    );
  }

  @override
  Future<void> removeService(AddedService service) async {
    for (final key in service.keys.values.whereType<int>()) {
      _characteristics.remove(key);
    }
    _manager.removeService(service.native!.ios!);
  }

  @override
  Future<void> notify(Object key, Uint8List value, Central central) async {
    final characteristic = _characteristics[key as int];
    if (characteristic == null) {
      throw const NativeOperationException('The characteristic was removed');
    }
    final data = value.toNSData();
    final centrals = objc.NSArray.of([(central as IosRemoteCentral).central]);
    while (!_manager.updateValue(
      data,
      forCharacteristic: characteristic,
      onSubscribedCentrals: centrals,
    )) {
      if (_closed) throw const DisconnectedException('The server closed');
      BtLog.server.warning(
        () =>
            '${central.id}: transmit queue full; waiting for '
            'peripheralManagerIsReadyToUpdateSubscribers',
      );
      await (_ready ??= Completer()).future;
    }
  }

  @override
  Future<void> requestConnectionPriority(
    Central central,
    ConnectionPriority priority,
  ) async => _manager.setDesiredConnectionLatency(switch (priority) {
    ConnectionPriority.high =>
      CBPeripheralManagerConnectionLatency
          .CBPeripheralManagerConnectionLatencyLow,
    ConnectionPriority.balanced =>
      CBPeripheralManagerConnectionLatency
          .CBPeripheralManagerConnectionLatencyMedium,
    ConnectionPriority.lowPower =>
      CBPeripheralManagerConnectionLatency
          .CBPeripheralManagerConnectionLatencyHigh,
  }, forCentral: (central as IosRemoteCentral).central);

  @override
  Future<void> close() async {
    _closed = true;
    _manager.removeAllServices();
    _requests.failAny(const DisconnectedException('The server closed'));
    _readyToUpdate();
    _role.serverClosed(this);
    await _events.close();
  }

  void didAddService(objc.NSError? error) => error == null
      ? _requests.complete(_addService, null)
      : _requests.fail(_addService, errorOf(error, 'addService'));

  void didReceiveRead(CBATTRequest request) => _events.add(
    ReadRequested(
      _central(request.central),
      keyOf(request.characteristic),
      request.offset,
      (error, [value]) {
        if (value != null) request.value = value.toNSData();
        _respond(request, error);
      },
    ),
  );

  /// CoreBluetooth does not say whether a write expects a response; it does
  /// when the characteristic allows writes with response.
  void didReceiveWrites(objc.NSArray array) {
    final requests = listOf(array, CBATTRequest.as);
    if (requests.isEmpty) return;
    final first = requests.first;
    final withResponse = requests.any(
      (r) =>
          r.characteristic.properties &
              CBCharacteristicProperties.CBCharacteristicPropertyWrite !=
          0,
    );
    _events.add(
      WriteRequested(
        _central(first.central),
        assembleWrites([
          for (final request in requests)
            (
              key: keyOf(request.characteristic),
              offset: request.offset,
              value: request.value?.toList() ?? Uint8List(0),
            ),
        ]),
        withResponse ? (error, [_]) => _respond(first, error) : null,
      ),
    );
  }

  void didChangeSubscription(
    CBCentral central,
    CBCharacteristic characteristic, {
    required bool subscribed,
  }) => _events.add(
    SubscriptionChanged(
      _central(central),
      keyOf(characteristic),
      subscribed: subscribed,
    ),
  );

  void readyToUpdate() => _readyToUpdate();

  void _readyToUpdate() {
    _ready?.complete();
    _ready = null;
  }

  void _respond(CBATTRequest request, GattError? error) =>
      _manager.respondToRequest(
        request,
        withResult: CBATTError.fromValue(error?.code ?? 0),
      );

  IosRemoteCentral _central(CBCentral central) {
    final id = central.identifier.UUIDString.toDartString();
    return _centrals[id] ??= IosRemoteCentral(central, id);
  }

  static CBMutableCharacteristic _characteristic(LocalCharacteristic local) {
    if (local.properties.broadcast) {
      throw const UnsupportedFeatureException(
        'broadcastCharacteristic',
        'iOS does not allow broadcast on local characteristics',
      );
    }
    final characteristic = CBMutableCharacteristic.alloc().initWithType(
      cbUuid(local.uuid),
      properties: local.properties.bits,
      value: null,
      permissions: _permissions(local.permissions),
    );
    if (local.descriptors.isNotEmpty) {
      characteristic.descriptors$1 = objc.NSArray.of(
        local.descriptors.map(_descriptor),
      );
    }
    return characteristic;
  }

  static CBMutableDescriptor _descriptor(LocalDescriptor local) {
    if (local.onRead != null || local.onWrite != null || local.isWritable) {
      throw const UnsupportedFeatureException(
        'dynamicDescriptor',
        'iOS serves descriptors with fixed values only',
      );
    }
    final objc.ObjCObject value;
    if (local.uuid == LocalDescriptor.userDescriptionUuid) {
      value = utf8.decode(local.value).toNSString();
    } else if (local.uuid == LocalDescriptor.presentationFormatUuid) {
      value = local.value.toNSData();
    } else {
      throw UnsupportedFeatureException(
        'descriptor',
        'iOS serves only the User Description and Presentation Format '
            'descriptors, not ${local.uuid}',
      );
    }
    return CBMutableDescriptor.alloc().initWithType(
      cbUuid(local.uuid),
      value: value,
    );
  }

  static int _permissions(Set<AttributePermission> permissions) {
    const flags = {
      AttributePermission.read:
          CBAttributePermissions.CBAttributePermissionsReadable,
      AttributePermission.readEncrypted:
          CBAttributePermissions.CBAttributePermissionsReadEncryptionRequired,
      AttributePermission.write:
          CBAttributePermissions.CBAttributePermissionsWriteable,
      AttributePermission.writeEncrypted:
          CBAttributePermissions.CBAttributePermissionsWriteEncryptionRequired,
    };
    return permissions.fold(0, (bits, p) => bits | flags[p]!);
  }
}

/// A central that reached this device's GATT server.
final class IosRemoteCentral implements Central {
  IosRemoteCentral(this.central, this.id);

  final CBCentral central;

  @override
  final String id;

  @override
  int get maximumUpdateLength => central.maximumUpdateValueLength;

  @override
  CentralHandle get native => IosHandle(central);
}
