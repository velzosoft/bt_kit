import 'dart:async';
import 'dart:typed_data';

import '../central/native_types.dart';
import '../central/peripheral.dart' show Timeouts;
import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../core/operation_queue.dart';
import '../models/connection_priority.dart';
import '../platform/peripheral_role_backend.dart';
import 'local_gatt.dart';

/// This device's GATT server, opened with `BtKit.openGattServer`.
///
/// Reads and writes from centrals are answered automatically: attributes
/// without handlers serve and store their value, attributes with handlers
/// delegate to them. Long reads and prepared writes are handled for you.
final class GattServer {
  GattServer._(this._backend) {
    _events = _backend.events.listen(_onEvent);
  }

  final ServerBackend _backend;
  late final StreamSubscription<ServerEvent> _events;
  final _changes = OperationQueue(log: BtLog.server);
  final _added = <LocalService, AddedService>{};
  final _keys = <LocalAttribute, Object>{};
  final _attributes = <Object, LocalAttribute>{};
  final _values = <LocalAttribute, Uint8List>{};
  final _centrals = <String, Central>{};
  final _subscribers = <LocalCharacteristic, Set<Central>>{};
  final _longReads = <(String, Object), Uint8List>{};
  final _notifications = <String, OperationQueue>{};
  final _centralChanges = StreamController<Set<Central>>.broadcast();
  final _subscriptionChanges = StreamController<SubscriptionChange>.broadcast();
  var _closed = false;

  /// How long a [ReadHandler] or [WriteHandler] may take before the central
  /// receives an error. Centrals give up after 30 seconds.
  Duration requestTimeout = const Duration(seconds: 10);

  /// `BluetoothGattServer` on Android, `CBPeripheralManager` on iOS.
  ServerHandle get native => _backend.native;

  List<LocalService> get services => List.unmodifiable(_added.keys);

  /// Centrals connected to this server. iOS only reports a central once it
  /// subscribes or sends a request.
  Set<Central> get centrals => Set.unmodifiable(_centrals.values);

  Stream<Set<Central>> get centralChanges => _centralChanges.stream;

  Stream<SubscriptionChange> get subscriptionChanges =>
      _subscriptionChanges.stream;

  bool get isClosed => _closed;

  Set<Central> subscribers(LocalCharacteristic characteristic) =>
      Set.unmodifiable(_subscribers[characteristic] ?? const <Central>{});

  /// The value served for [attribute] when it has no [ReadHandler].
  Uint8List value(LocalAttribute attribute) =>
      _values[attribute] ?? attribute.value;

  LocalServiceHandle? nativeService(LocalService service) =>
      _added[service]?.native;

  LocalCharacteristicHandle? nativeCharacteristic(
    LocalCharacteristic characteristic,
  ) {
    for (final added in _added.values) {
      if (added.natives[characteristic] case final handle?) return handle;
    }
    return null;
  }

  /// Adds [service]. Add the services it includes first; calls that have
  /// not completed yet count.
  Future<void> addService(
    LocalService service, {
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) async {
    _checkOpen();
    if (_added.containsKey(service)) return;
    await _changes.run(
      'addService ${service.uuid}',
      () => _add(service),
      timeout: timeout,
      cancelToken: cancelToken,
    );
  }

  /// Records the service as soon as the platform added it, even if the
  /// caller stopped waiting, because the platform serves it from then on.
  Future<void> _add(LocalService service) async {
    final included = [
      for (final other in service.includedServices)
        _added[other] ??
            (throw ArgumentError(
              'Add $other before $service, which includes it',
            )),
    ];
    final added = await _backend.addService(service, included);
    _added[service] = added;
    for (final MapEntry(key: attribute, value: key) in added.keys.entries) {
      _keys[attribute] = key;
      _attributes[key] = attribute;
    }
  }

  Future<void> removeService(
    LocalService service, {
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) async {
    _checkOpen();
    final added = _added.remove(service);
    if (added == null) return;
    for (final MapEntry(key: attribute, value: key) in added.keys.entries) {
      _keys.remove(attribute);
      _attributes.remove(key);
      _values.remove(attribute);
      _subscribers.remove(attribute);
    }
    await _changes.run(
      'removeService ${service.uuid}',
      () => _backend.removeService(added),
      timeout: timeout,
      cancelToken: cancelToken,
    );
  }

  /// Changes the value served to reads, without notifying anyone.
  void setValue(LocalAttribute attribute, List<int> value) {
    _checkLength(value);
    _values[attribute] = Uint8List.fromList(value);
  }

  /// Sets [characteristic]'s value and sends it to its subscribers, or to
  /// those of [centrals] that are subscribed.
  ///
  /// Completes once every notification left the device (Android) or was
  /// queued for sending (iOS). Each central gets its own queue, so one slow
  /// central does not hold back the others. A value longer than a central's
  /// [Central.maximumUpdateLength] is refused with an [ArgumentError].
  Future<void> notify(
    LocalCharacteristic characteristic,
    List<int> value, {
    Iterable<Central>? centrals,
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) async {
    _checkOpen();
    final key = _keys[characteristic];
    if (key == null) throw ArgumentError('$characteristic is not added');
    if (!characteristic.canNotify) {
      throw ArgumentError('$characteristic does not notify or indicate');
    }
    _checkLength(value);
    final bytes = Uint8List.fromList(value);
    _values[characteristic] = bytes;
    final only = centrals?.map((c) => c.id).toSet();
    final targets = [
      for (final central in _subscribers[characteristic] ?? const <Central>{})
        if (only == null || only.contains(central.id)) central,
    ];
    for (final central in targets) {
      if (bytes.length > central.maximumUpdateLength) {
        throw ArgumentError(
          'The value is ${bytes.length} bytes; ${central.id} accepts '
          '${central.maximumUpdateLength}',
        );
      }
    }
    await Future.wait([
      for (final central in targets)
        _notifications
            .putIfAbsent(
              central.id,
              () => OperationQueue(log: BtLog.server, label: central.id),
            )
            .run(
              'notify ${characteristic.uuid}',
              () => _backend.notify(key, bytes, central),
              timeout: timeout,
              cancelToken: cancelToken,
            ),
    ]);
  }

  /// Asks [central] for a shorter or longer connection interval (iOS).
  ///
  /// iOS passes the request on without reporting the outcome. Android
  /// servers cannot ask; check `capabilities.serverConnectionPriority`.
  Future<void> requestConnectionPriority(
    Central central,
    ConnectionPriority priority,
  ) async {
    _checkOpen();
    BtLog.server.info(() => '${central.id}: asking for ${priority.name}');
    await _backend.requestConnectionPriority(central, priority);
  }

  /// Removes every service and stops serving. Subscribed centrals see the
  /// services disappear.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _events.cancel();
    for (final queue in _notifications.values) {
      queue.failWaiting(const DisconnectedException('The server closed'));
    }
    await _backend.close();
    await _centralChanges.close();
    await _subscriptionChanges.close();
  }

  void _onEvent(ServerEvent event) {
    if (event is CentralDisconnected) {
      final known = _centrals[event.central.id];
      if (known != null) _forget(known);
      return;
    }
    final central = _central(event.central);
    switch (event) {
      case CentralConnected() || CentralDisconnected():
        break;
      case ReadRequested():
        unawaited(_read(central, event));
      case WriteRequested():
        unawaited(_write(central, event));
      case SubscriptionChanged(:final key, :final subscribed):
        _subscriptionChanged(central, key, subscribed);
    }
  }

  Central _central(Central reported) {
    final known = _centrals[reported.id];
    if (known != null) return known;
    _centrals[reported.id] = reported;
    BtLog.server.info(() => '${reported.id}: connected');
    _centralChanges.add(centrals);
    return reported;
  }

  void _forget(Central central) {
    if (_centrals.remove(central.id) == null) return;
    BtLog.server.info(() => '${central.id}: disconnected');
    for (final MapEntry(key: characteristic, value: subscribers)
        in _subscribers.entries) {
      if (subscribers.remove(central)) {
        _subscriptionChanges.add(
          SubscriptionChange(central, characteristic, subscribed: false),
        );
      }
    }
    _longReads.removeWhere((key, _) => key.$1 == central.id);
    _notifications
        .remove(central.id)
        ?.failWaiting(const DisconnectedException('The central disconnected'));
    _centralChanges.add(centrals);
  }

  Future<void> _read(Central central, ReadRequested request) async {
    final attribute = _attributes[request.key];
    if (attribute == null) return request.respond(GattError.invalidHandle);
    if (!attribute.isReadable) {
      return request.respond(GattError.readNotPermitted);
    }
    final cacheKey = (central.id, request.key);
    try {
      final Uint8List full;
      if (request.offset == 0) {
        full = await _currentValue(central, attribute);
        _longReads[cacheKey] = full;
      } else {
        full = _longReads[cacheKey] ?? value(attribute);
      }
      if (request.offset > full.length) {
        return request.respond(GattError.invalidOffset);
      }
      final served = Uint8List.sublistView(full, request.offset);
      BtLog.server.finer(
        () =>
            '${central.id}: read ${attribute.uuid} at ${request.offset}: '
            '${hex(served)}',
      );
      request.respond(null, served);
    } on GattException catch (e) {
      request.respond(e.error);
    } on Object {
      request.respond(GattError.unlikelyError);
    }
  }

  Future<Uint8List> _currentValue(
    Central central,
    LocalAttribute attribute,
  ) async {
    final handler = attribute.onRead;
    if (handler == null) return value(attribute);
    final result = await Future.sync(
      () => handler(ReadRequest(central, attribute)),
    ).timeout(requestTimeout);
    _checkLength(result);
    return Uint8List.fromList(result);
  }

  /// Validates every write first, so that a rejected prepared-write queue
  /// changes nothing, then applies them in order.
  Future<void> _write(Central central, WriteRequested request) async {
    for (final write in request.writes) {
      if (_check(write) case final error?) {
        return request.respond?.call(error);
      }
    }
    for (final write in request.writes) {
      final attribute = _attributes[write.key]!;
      BtLog.server.finer(
        () =>
            '${central.id}: write ${attribute.uuid} at ${write.offset}: '
            '${hex(write.value)}',
      );
      final next = write.offset == 0
          ? write.value
          : Uint8List.fromList([
              ...value(attribute).take(write.offset),
              ...write.value,
            ]);
      final error = await _apply(
        central,
        attribute,
        next,
        withResponse: request.withResponse,
      );
      if (error != null) return request.respond?.call(error);
    }
    request.respond?.call(null);
  }

  GattError? _check(AttributeWrite write) {
    final attribute = _attributes[write.key];
    if (attribute == null) return GattError.invalidHandle;
    if (!attribute.isWritable) return GattError.writeNotPermitted;
    if (write.offset > value(attribute).length) return GattError.invalidOffset;
    if (write.offset + write.value.length > LocalAttribute.maxLength) {
      return GattError.invalidAttributeValueLength;
    }
    return null;
  }

  Future<GattError?> _apply(
    Central central,
    LocalAttribute attribute,
    Uint8List next, {
    required bool withResponse,
  }) async {
    try {
      final handler = attribute.onWrite;
      if (handler != null) {
        await Future.sync(
          () => handler(
            WriteRequest(central, attribute, next, withResponse: withResponse),
          ),
        ).timeout(requestTimeout);
      }
      _values[attribute] = next;
      return null;
    } on GattException catch (e) {
      return e.error;
    } on Object {
      return GattError.unlikelyError;
    }
  }

  void _subscriptionChanged(Central central, Object key, bool subscribed) {
    final characteristic = _attributes[key];
    if (characteristic is! LocalCharacteristic) return;
    final subscribers = _subscribers.putIfAbsent(characteristic, () => {});
    final changed = subscribed
        ? subscribers.add(central)
        : subscribers.remove(central);
    if (changed) {
      BtLog.server.info(
        () =>
            '${central.id}: ${subscribed ? 'subscribed to' : 'left'} '
            '${characteristic.uuid}',
      );
      _subscriptionChanges.add(
        SubscriptionChange(central, characteristic, subscribed: subscribed),
      );
    }
  }

  void _checkOpen() {
    if (_closed) throw StateError('The GATT server is closed');
  }

  static void _checkLength(List<int> value) {
    if (value.length > LocalAttribute.maxLength) {
      throw ArgumentError.value(value.length, 'value', 'longer than 512 bytes');
    }
  }
}

/// Creates a [GattServer] for a backend; used by `BtKit` only.
GattServer createGattServer(ServerBackend backend) => GattServer._(backend);
