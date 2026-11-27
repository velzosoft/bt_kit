part of 'fake_bluetooth.dart';

/// A simulated remote peripheral, added to a [FakeBluetooth].
///
/// It serves [services] the way a `GattServer` would: attributes without
/// handlers serve and store their value, and handlers can answer or reject
/// with a [GattException].
final class FakePeripheral {
  FakePeripheral({
    required this.id,
    this._name,
    this.advertisement = const AdvertisementData(),
    this.rssi = -60,
    List<LocalService> services = const [],
    this.connectable = true,
    this.maxMtu = 247,
    this._bondState = BondState.none,
    this.acceptsPairing = true,
    this.pairingTime = Duration.zero,
  }) : _initialServices = services;

  /// A MAC address, as on Android, or a UUID, as on iOS.
  final String id;

  /// What scans report. Change it and call [advertise] to send it.
  AdvertisementData advertisement;

  int rssi;

  /// Whether connection attempts succeed; when false they never complete,
  /// as with a device that stopped accepting connections.
  bool connectable;

  /// The largest MTU this peripheral accepts.
  int maxMtu;

  /// Whether pairing succeeds, as if the user confirmed it; when false,
  /// `createBond` fails with `BondException`.
  bool acceptsPairing;

  /// How long pairing takes, as if the user took that long to confirm.
  Duration pairingTime;

  /// How many times the app cleared this peripheral's GATT cache.
  int cacheClears = 0;

  final List<LocalService> _initialServices;
  late final _link = _FakeLink(this);
  late final _backend = _FakeServerBackend(this);
  late final GattServer _server = createGattServer(_backend);
  late final Future<void> _ready = Future.wait([
    for (final service in _initialServices) _server.addService(service),
  ]);
  FakeBluetooth? _bluetooth;
  String? _name;
  var _inRange = true;
  BondState _bondState;
  final _bondStates = StreamController<BondState>.broadcast(sync: true);

  /// The bond with the phone. Changing it reports a bond change.
  BondState get bondState => _bondState;

  set bondState(BondState state) {
    if (state == _bondState) return;
    _bondState = state;
    _bondStates.add(state);
  }

  /// The GAP name. Changing it while connected reports a name change.
  String? get name => _name;

  set name(String? name) {
    _name = name;
    if (isConnected) _link._updates.add(NameUpdate(name));
  }

  /// Out of range, the peripheral stops advertising and its connection
  /// drops with [DisconnectCause.linkLoss].
  bool get inRange => _inRange;

  set inRange(bool inRange) {
    _inRange = inRange;
    if (inRange) {
      advertise();
    } else {
      _link._drop(DisconnectCause.linkLoss);
    }
  }

  bool get isConnected =>
      _link.connectionState == BluetoothConnectionState.connected;

  List<LocalService> get services {
    _ready;
    return _server.services;
  }

  int get mtu => _link.mtu;

  PhyInfo get phy => _link._phy;

  /// The priority the app asked for last on this connection.
  ConnectionPriority? get connectionPriority => _link._priority;

  /// How the app subscribed to [characteristic], or null if it did not.
  NotifyMode? subscription(LocalCharacteristic characteristic) =>
      _link._subscriptions[_backend.keys[characteristic]];

  /// Sends an advertisement to running scans, optionally changing what it
  /// carries first.
  void advertise({AdvertisementData? data, int? rssi}) {
    if (data != null) advertisement = data;
    if (rssi != null) this.rssi = rssi;
    _bluetooth?._advertised(this);
  }

  /// Ends the connection from the peripheral's side.
  void disconnect({DisconnectCause cause = DisconnectCause.remote}) =>
      _link._drop(cause);

  /// Stores [value] and pushes it to the app if it subscribed to
  /// [characteristic].
  Future<void> notify(
    LocalCharacteristic characteristic,
    List<int> value,
  ) async {
    await _ready;
    await _server.notify(characteristic, value);
  }

  /// The value served for [attribute] when it has no read handler; writes
  /// from the app change it.
  Uint8List value(LocalAttribute attribute) => _server.value(attribute);

  void setValue(LocalAttribute attribute, List<int> value) =>
      _server.setValue(attribute, value);

  /// Adds a service and, while connected, reports a Services Changed.
  Future<void> addService(LocalService service) async {
    await _ready;
    await _server.addService(service);
    _link._servicesChanged();
  }

  /// Removes a service and, while connected, reports a Services Changed.
  Future<void> removeService(LocalService service) async {
    await _ready;
    await _server.removeService(service);
    _link._servicesChanged();
  }

  @override
  String toString() => 'FakePeripheral($id)';
}

/// Pairing with a [FakePeripheral], answered by [FakePeripheral.acceptsPairing].
final class _FakeBond implements BondBackend {
  _FakeBond(this._peripheral);

  final FakePeripheral _peripheral;

  @override
  BondState get bondState => _peripheral.bondState;

  @override
  Stream<BondState> get bondStates => _peripheral._bondStates.stream;

  @override
  Future<void> createBond() async {
    if (bondState == BondState.bonded) return;
    _peripheral.bondState = BondState.bonding;
    await Future<void>.delayed(_peripheral.pairingTime);
    if (bondState != BondState.bonding) {
      throw const BondException('Pairing was cancelled');
    }
    if (_peripheral.acceptsPairing) {
      _peripheral.bondState = BondState.bonded;
    } else {
      _peripheral.bondState = BondState.none;
      throw const BondException('Pairing failed or was rejected');
    }
  }

  @override
  void cancelBond() {
    if (bondState == BondState.bonding) {
      _peripheral.bondState = BondState.none;
    }
  }

  @override
  Future<void> removeBond() async => _peripheral.bondState = BondState.none;
}

final class _FakeServerBackend implements ServerBackend {
  _FakeServerBackend(this._peripheral);

  final FakePeripheral _peripheral;
  final _events = _DirectStream<ServerEvent>();
  final keys = <LocalAttribute, int>{};
  var _nextKey = 0;

  @override
  ServerHandle get native => _noNative();

  @override
  Stream<ServerEvent> get events => _events;

  @override
  Future<AddedService> addService(
    LocalService service,
    List<AddedService> included,
  ) async {
    final added = <LocalAttribute, Object>{};
    for (final characteristic in service.characteristics) {
      added[characteristic] = keys[characteristic] = _nextKey++;
      for (final descriptor in characteristic.descriptors) {
        added[descriptor] = keys[descriptor] = _nextKey++;
      }
    }
    return AddedService(service, added);
  }

  @override
  Future<void> removeService(AddedService service) async =>
      keys.removeWhere((attribute, _) => service.keys.containsKey(attribute));

  @override
  Future<void> notify(Object key, Uint8List value, Central central) async =>
      _peripheral._link._push(key, value);

  @override
  Future<void> requestConnectionPriority(
    Central central,
    ConnectionPriority priority,
  ) async {}

  @override
  Future<void> close() async => _events.close();

  void emit(ServerEvent event) => _events.add(event);
}

/// A stream that calls its listener at once, in the zone of whoever adds
/// the event.
///
/// The fake peripheral's server answers requests as they arrive, so its
/// work runs in the zone of the request, the test's, even when the
/// peripheral was created elsewhere, such as in `setUp`.
final class _DirectStream<T> extends Stream<T> {
  _DirectSubscription<T>? _subscription;

  void add(T event) => _subscription?._onData?.call(event);

  void close() => _subscription?._onDone?.call();

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (_subscription != null) throw StateError('Already listened to');
    return _subscription = _DirectSubscription(this, onData, onDone);
  }
}

final class _DirectSubscription<T> implements StreamSubscription<T> {
  _DirectSubscription(this._stream, this._onData, this._onDone);

  final _DirectStream<T> _stream;
  void Function(T)? _onData;
  void Function()? _onDone;

  @override
  Future<void> cancel() async {
    if (identical(_stream._subscription, this)) _stream._subscription = null;
  }

  @override
  void onData(void Function(T data)? handleData) => _onData = handleData;

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) => _onDone = handleDone;

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  bool get isPaused => false;

  @override
  Future<E> asFuture<E>([E? futureValue]) =>
      throw UnsupportedError('Not used by the fake server');
}
