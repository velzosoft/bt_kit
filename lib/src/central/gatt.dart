part of 'peripheral.dart';

/// A GATT service discovered on a [Peripheral].
final class GattService {
  GattService._(this.peripheral, DiscoveredService discovered)
    : uuid = discovered.uuid,
      isPrimary = discovered.isPrimary,
      _key = discovered.key,
      _includedKeys = discovered.included,
      _native = discovered.native {
    characteristics = [
      for (final c in discovered.characteristics) GattCharacteristic._(this, c),
    ];
  }

  final Peripheral peripheral;
  final BluetoothUuid uuid;
  final bool isPrimary;
  late final List<GattCharacteristic> characteristics;

  /// The services this one includes, from the same
  /// [Peripheral.discoverServices].
  late final List<GattService> includedServices;

  final Object _key;
  final List<Object> _includedKeys;
  final ServiceHandle? _native;
  GattService? _primary;
  var _invalidated = false;

  ServiceHandle get native => _native ?? _noNative();

  /// The primary service that includes this one, or null when none does.
  GattService? get primaryService => _primary;

  void _resolveIncluded(Map<Object, GattService> services) {
    includedServices = List.unmodifiable([
      for (final key in _includedKeys) ?services[key],
    ]);
    if (!isPrimary) return;
    for (final included in includedServices) {
      included._primary ??= this;
    }
  }

  /// Whether the peripheral removed or changed this service; see
  /// [Peripheral.servicesChanged].
  bool get isInvalidated => _invalidated;

  @override
  String toString() => 'GattService($uuid)';
}

/// A GATT characteristic.
final class GattCharacteristic {
  GattCharacteristic._(this.service, this._discovered)
    : uuid = _discovered.uuid,
      properties = CharacteristicProperties(_discovered.properties) {
    descriptors = [
      for (final d in _discovered.descriptors) GattDescriptor._(this, d),
    ];
  }

  final GattService service;
  final BluetoothUuid uuid;
  final CharacteristicProperties properties;
  late final List<GattDescriptor> descriptors;
  final DiscoveredCharacteristic _discovered;
  final _lastValue = _LastValue();

  Object get _key => _discovered.key;

  Peripheral get peripheral => service.peripheral;

  CharacteristicHandle get native => _discovered.native ?? _noNative();

  /// The value last read, written or pushed by the peripheral.
  Uint8List? get lastValue => _lastValue.value;

  /// Every value read, successfully written or pushed by the peripheral.
  ///
  /// Listening does not turn pushes on; [subscribe] does.
  Stream<Uint8List> get valueChanges => _lastValue.changes;

  /// Whether pushes are on through [subscribe].
  bool get isNotifying => peripheral._subscriptions[_key]?.isEnabled ?? false;

  Future<Uint8List> read({
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) => peripheral._runOn(
    service,
    'read $uuid',
    () async {
      final value = await peripheral._backend.readCharacteristic(_discovered);
      _log('read', value);
      _lastValue.update(value);
      return value;
    },
    timeout,
    cancelToken,
  );

  /// Writes [value]. A write without response completes once the platform
  /// has accepted it, not when the peripheral has received it.
  Future<void> write(
    List<int> value, {
    bool withResponse = true,
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) {
    final bytes = Uint8List.fromList(value);
    return peripheral._runOn(
      service,
      'write $uuid',
      () async {
        _log('write', bytes);
        await peripheral._backend.writeCharacteristic(
          _discovered,
          bytes,
          withResponse: withResponse,
        );
        _lastValue.update(bytes);
      },
      timeout,
      cancelToken,
    );
  }

  /// Writes [value] in pieces of [Peripheral.maximumWriteLength], for
  /// values longer than one write carries, such as a firmware image.
  ///
  /// The peripheral sees each piece as an ordinary write; the protocol on
  /// top decides how they join. The queue stays held across the pieces, so
  /// no other operation on this peripheral runs between them. [onProgress]
  /// reports the bytes sent after each piece. The whole write may take
  /// [timeout] per piece.
  Future<void> writeChunked(
    List<int> value, {
    bool withResponse = false,
    void Function(int sent, int total)? onProgress,
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) {
    final bytes = Uint8List.fromList(value);
    final pieces = max(
      1,
      (bytes.length / peripheral.maximumWriteLength(withResponse: withResponse))
          .ceil(),
    );
    final budget = timeout * pieces;
    return peripheral._runOn(
      service,
      'writeChunked $uuid (${bytes.length} bytes)',
      () async {
        final clock = Stopwatch()..start();
        final length = peripheral.maximumWriteLength(
          withResponse: withResponse,
        );
        var sent = 0;
        do {
          cancelToken?.throwIfCancelled();
          if (clock.elapsed > budget) {
            throw OperationTimeoutException('writeChunked $uuid', budget);
          }
          final end = min(sent + length, bytes.length);
          final piece = Uint8List.sublistView(bytes, sent, end);
          _log('write', piece);
          await peripheral._backend.writeCharacteristic(
            _discovered,
            piece,
            withResponse: withResponse,
          );
          sent = end;
          onProgress?.call(sent, bytes.length);
        } while (sent < bytes.length);
        _lastValue.update(bytes);
      },
      budget,
      cancelToken,
    );
  }

  /// Values the peripheral pushes by notification or indication.
  ///
  /// Listening turns pushes on in [mode]; cancelling the last subscription
  /// turns them off again. Listeners share one subscription, so asking for
  /// another mode while one is active throws a [StateError]. Only Android
  /// can choose the mode when the characteristic supports both; elsewhere a
  /// specific mode fails with [UnsupportedFeatureException].
  ///
  /// The stream ends with [DisconnectedException] when the link drops.
  Stream<Uint8List> subscribe({NotifyMode mode = NotifyMode.auto}) =>
      peripheral._subscribe(this, mode);

  void _log(String operation, Uint8List value) => BtLog.gatt.finer(
    () => '${peripheral.id}: $operation $uuid ${hex(value)}',
  );

  @override
  String toString() => 'GattCharacteristic($uuid)';
}

/// A GATT descriptor.
final class GattDescriptor {
  GattDescriptor._(this.characteristic, this._discovered)
    : uuid = _discovered.uuid;

  final GattCharacteristic characteristic;
  final BluetoothUuid uuid;
  final DiscoveredDescriptor _discovered;
  final _lastValue = _LastValue();

  Peripheral get peripheral => characteristic.peripheral;

  DescriptorHandle get native => _discovered.native ?? _noNative();

  /// The value last read or written.
  Uint8List? get lastValue => _lastValue.value;

  /// Every value read or successfully written.
  Stream<Uint8List> get valueChanges => _lastValue.changes;

  Future<Uint8List> read({
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) => peripheral._runOn(
    characteristic.service,
    'read descriptor $uuid',
    () async {
      final value = await peripheral._backend.readDescriptor(_discovered);
      _lastValue.update(value);
      return value;
    },
    timeout,
    cancelToken,
  );

  Future<void> write(
    List<int> value, {
    Duration timeout = Timeouts.gatt,
    CancelToken? cancelToken,
  }) {
    final bytes = Uint8List.fromList(value);
    return peripheral._runOn(
      characteristic.service,
      'write descriptor $uuid',
      () async {
        await peripheral._backend.writeDescriptor(_discovered, bytes);
        _lastValue.update(bytes);
      },
      timeout,
      cancelToken,
    );
  }

  @override
  String toString() => 'GattDescriptor($uuid)';
}

final class _LastValue {
  Uint8List? value;
  StreamController<Uint8List>? _changes;

  Stream<Uint8List> get changes =>
      (_changes ??= StreamController<Uint8List>.broadcast()).stream;

  void update(Uint8List next) {
    value = next;
    _changes?.add(next);
  }
}
