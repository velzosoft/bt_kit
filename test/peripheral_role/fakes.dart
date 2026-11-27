import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/platform/peripheral_role_backend.dart';

final class FakeCentral implements Central {
  FakeCentral(this.id, {this.maximumUpdateLength = 20});

  @override
  final String id;

  @override
  final int maximumUpdateLength;

  @override
  CentralHandle get native => throw UnimplementedError();
}

/// A server backend that records what the GATT server asks of the platform
/// and lets tests play the centrals.
final class FakeServerBackend implements ServerBackend {
  final _events = StreamController<ServerEvent>();
  final notifications = <(Object, List<int>, String)>[];
  final keys = <LocalAttribute, Object>{};
  Completer<void>? notificationGate;
  var closed = false;
  var _nextKey = 0;

  @override
  ServerHandle get native => throw UnimplementedError();

  @override
  Stream<ServerEvent> get events => _events.stream;

  final included = <LocalService, List<LocalService>>{};
  final priorities = <(String, ConnectionPriority)>[];

  @override
  Future<AddedService> addService(
    LocalService service,
    List<AddedService> included,
  ) async {
    this.included[service] = [for (final other in included) other.service];
    final added = <LocalAttribute, Object>{};
    for (final characteristic in service.characteristics) {
      added[characteristic] = _nextKey++;
      for (final descriptor in characteristic.descriptors) {
        added[descriptor] = _nextKey++;
      }
    }
    keys.addAll(added);
    return AddedService(service, added);
  }

  @override
  Future<void> removeService(AddedService service) async {}

  @override
  Future<void> notify(Object key, Uint8List value, Central central) async {
    notifications.add((key, value, central.id));
    await notificationGate?.future;
  }

  @override
  Future<void> requestConnectionPriority(
    Central central,
    ConnectionPriority priority,
  ) async => priorities.add((central.id, priority));

  @override
  Future<void> close() async {
    closed = true;
    await _events.close();
  }

  void emit(ServerEvent event) => _events.add(event);

  Future<(GattError?, Uint8List?)> read(
    Central central,
    LocalAttribute attribute, {
    int offset = 0,
  }) {
    final response = Completer<(GattError?, Uint8List?)>();
    emit(
      ReadRequested(
        central,
        keys[attribute] ?? -1,
        offset,
        (error, [value]) => response.complete((error, value)),
      ),
    );
    return response.future;
  }

  Future<GattError?> write(
    Central central,
    List<(LocalAttribute, int, List<int>)> writes,
  ) {
    final response = Completer<GattError?>();
    emit(
      WriteRequested(central, [
        for (final (attribute, offset, value) in writes)
          (
            key: keys[attribute]!,
            offset: offset,
            value: Uint8List.fromList(value),
          ),
      ], (error, [_]) => response.complete(error)),
    );
    return response.future;
  }
}
