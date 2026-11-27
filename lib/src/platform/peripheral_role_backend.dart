import 'dart:typed_data';

import '../central/native_types.dart';
import '../core/bluetooth_uuid.dart';
import '../core/exceptions.dart';
import '../models/adapter_state.dart';
import '../models/advertise_options.dart';
import '../models/connection_priority.dart';
import '../peripheral_role/local_gatt.dart';
import 'channel_backend.dart';

/// The local device in the peripheral role, implemented on top of Layer 1.
abstract interface class PeripheralRoleBackend {
  /// The adapter state as the peripheral role sees it. On iOS this is the
  /// state of `CBPeripheralManager`, which starts out unknown.
  Future<AdapterState> settledState();

  Future<ServerBackend> openServer();

  /// Completes once advertising has started.
  Future<AdvertisingBackend> startAdvertising(AdvertiseOptions options);

  Future<L2capServerBackend> publishL2cap({required bool secure});

  /// What iOS restored for the peripheral role when it relaunched the app.
  /// The last restoration is replayed to each new listener.
  Stream<PeripheralRoleRestoration> get restorations;
}

typedef PeripheralRoleRestoration = ({
  List<BluetoothUuid> services,
  bool advertising,
});

/// A GATT server. Requests arrive as [events]; the server answers each
/// through its `respond` callback exactly once.
abstract interface class ServerBackend {
  ServerHandle get native;
  Stream<ServerEvent> get events;

  /// Adds [service], which includes the already added [included], and
  /// returns the keys its attributes carry in [events].
  Future<AddedService> addService(
    LocalService service,
    List<AddedService> included,
  );

  Future<void> removeService(AddedService service);

  /// Sends [value] to [central] as a notification or indication, whichever
  /// the central subscribed to, and completes once the platform took it.
  Future<void> notify(Object key, Uint8List value, Central central);

  /// Asks [central] for [priority]; completes once the platform took the
  /// request.
  Future<void> requestConnectionPriority(
    Central central,
    ConnectionPriority priority,
  );

  Future<void> close();
}

abstract interface class AdvertisingBackend {
  AdvertisingHandle get native;

  /// Advertises [options] instead, and completes once the platform applied
  /// them. A failed update leaves the previous advertisement running where
  /// the platform allows.
  Future<void> update(AdvertiseOptions options);

  Future<void> stop();
}

final class AddedService {
  const AddedService(
    this.service,
    this.keys, {
    this.native,
    this.natives = const {},
  });

  final LocalService service;

  /// The key each attribute carries in [ServerEvent]s.
  final Map<LocalAttribute, Object> keys;
  final LocalServiceHandle? native;
  final Map<LocalCharacteristic, LocalCharacteristicHandle> natives;
}

/// Answers a request. Reads pass the value from the requested offset.
typedef Respond = void Function(GattError? error, [Uint8List? value]);

typedef AttributeWrite = ({Object key, int offset, Uint8List value});

sealed class ServerEvent {
  const ServerEvent(this.central);

  final Central central;
}

final class CentralConnected extends ServerEvent {
  const CentralConnected(super.central);
}

final class CentralDisconnected extends ServerEvent {
  const CentralDisconnected(super.central);
}

final class ReadRequested extends ServerEvent {
  const ReadRequested(super.central, this.key, this.offset, this.respond);

  final Object key;
  final int offset;
  final Respond respond;
}

/// One write, or a whole prepared-write queue at execution, with values
/// already assembled. [respond] is null when no response is expected,
/// unless the backend wants to know when the write was applied.
final class WriteRequested extends ServerEvent {
  const WriteRequested(
    super.central,
    this.writes,
    this.respond, {
    this._withResponse,
  });

  final List<AttributeWrite> writes;
  final Respond? respond;
  final bool? _withResponse;

  bool get withResponse => _withResponse ?? respond != null;
}

final class SubscriptionChanged extends ServerEvent {
  const SubscriptionChanged(
    super.central,
    this.key, {
    required this.subscribed,
  });

  final Object key;
  final bool subscribed;
}

/// Joins the pieces of each attribute's long write into one value, in the
/// order the attributes first appear.
List<AttributeWrite> assembleWrites(List<AttributeWrite> pieces) {
  final byKey = <Object, List<AttributeWrite>>{};
  for (final piece in pieces) {
    byKey.putIfAbsent(piece.key, () => []).add(piece);
  }
  return [
    for (final MapEntry(:key, value: parts) in byKey.entries)
      if (parts.length == 1) parts.single else _join(key, parts),
  ];
}

AttributeWrite _join(Object key, List<AttributeWrite> parts) {
  var start = parts.first.offset;
  var end = 0;
  for (final part in parts) {
    if (part.offset < start) start = part.offset;
    if (part.offset + part.value.length > end) {
      end = part.offset + part.value.length;
    }
  }
  final value = Uint8List(end - start);
  for (final part in parts) {
    value.setAll(part.offset - start, part.value);
  }
  return (key: key, offset: start, value: value);
}
