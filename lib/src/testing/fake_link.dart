part of 'fake_bluetooth.dart';

/// The app's connection to a [FakePeripheral]. Requests reach the
/// peripheral's `GattServer` as if this device were a central.
final class _FakeLink implements PeripheralBackend {
  _FakeLink(this._peripheral);

  static const _defaultMtu = 23;
  static const _defaultPhy = PhyInfo(tx: Phy.le1M, rx: Phy.le1M);

  final FakePeripheral _peripheral;
  final _states = StreamController<BluetoothConnectionState>.broadcast();
  final _notifications = StreamController<ValueNotification>.broadcast();
  final _updates = StreamController<LinkUpdate>.broadcast();
  final _subscriptions = <Object, NotifyMode>{};
  final _unanswered = <Completer<Object?>>{};
  late final _central = _AppCentral(this);
  var _state = BluetoothConnectionState.disconnected;
  DisconnectReason? _lastDisconnect;
  Completer<void>? _connecting;
  var _mtu = _defaultMtu;
  var _phy = _defaultPhy;
  ConnectionPriority? _priority;

  FakeBluetooth get _bluetooth =>
      _peripheral._bluetooth ??
      (throw StateError('Add ${_peripheral.id} to a FakeBluetooth first'));

  _FakeServerBackend get _server => _peripheral._backend;

  @override
  String get id => _peripheral.id;

  @override
  String? get name => _peripheral.name;

  @override
  PeripheralHandle get native => _noNative();

  @override
  BluetoothConnectionState get connectionState => _state;

  @override
  Stream<BluetoothConnectionState> get connectionStates => _states.stream;

  @override
  DisconnectReason? get lastDisconnect => _lastDisconnect;

  @override
  late final BondBackend bond = _FakeBond(_peripheral);

  @override
  Stream<DistanceMeasurement> measureDistance(
    DistanceMethod method,
    MeasurementRate rate,
  ) => Stream.error(
    const UnsupportedFeatureException(
      'channelSounding',
      'FakeBluetooth does not simulate ranging',
    ),
  );

  @override
  Stream<ValueNotification> get notifications => _notifications.stream;

  @override
  Stream<LinkUpdate> get updates => _updates.stream;

  @override
  int get mtu => _mtu;

  @override
  Future<void> connect({required bool autoConnect}) {
    _bluetooth;
    final connecting = _connecting = Completer<void>();
    _setState(BluetoothConnectionState.connecting);
    if (_peripheral.connectable && _peripheral.inRange) {
      scheduleMicrotask(() {
        if (!identical(_connecting, connecting)) return;
        _connecting = null;
        _setState(BluetoothConnectionState.connected);
        _server.emit(CentralConnected(_central));
        connecting.complete();
      });
    }
    return connecting.future;
  }

  @override
  Future<void> disconnect() async => _drop(DisconnectCause.requested);

  void _drop(DisconnectCause cause) {
    if (_state == BluetoothConnectionState.disconnected) return;
    final wasConnected = _state == BluetoothConnectionState.connected;
    _lastDisconnect = DisconnectReason(cause, at: DateTime.now());
    final BluetoothException error = wasConnected
        ? DisconnectedException('Disconnected', _lastDisconnect)
        : cause == DisconnectCause.requested
        ? const OperationCancelledException('Disconnected')
        : ConnectionException('Connection failed: ${cause.name}');
    _connecting?.completeError(error);
    _connecting = null;
    for (final request in _unanswered) {
      request.completeError(error);
    }
    _unanswered.clear();
    _subscriptions.clear();
    _mtu = _defaultMtu;
    _phy = _defaultPhy;
    _priority = null;
    if (wasConnected) _server.emit(CentralDisconnected(_central));
    _setState(BluetoothConnectionState.disconnected);
  }

  @override
  Future<List<DiscoveredService>> discoverServices() =>
      _request('discoverServices', () async => _discovery());

  @override
  Future<Uint8List> readCharacteristic(
    DiscoveredCharacteristic characteristic,
  ) => _request('read', () => _read(characteristic.key));

  @override
  Future<void> writeCharacteristic(
    DiscoveredCharacteristic characteristic,
    Uint8List value, {
    required bool withResponse,
  }) => _request(
    'write',
    () => _write(characteristic.key, value, withResponse: withResponse),
  );

  @override
  Future<void> setNotifying(
    DiscoveredCharacteristic characteristic,
    NotifyMode? mode,
  ) => _request(
    'setNotifying',
    () async => _subscribe(characteristic.key, mode),
  );

  @override
  Future<Uint8List> readDescriptor(DiscoveredDescriptor descriptor) =>
      _request('readDescriptor', () async {
        if (descriptor.key case (_cccd, final Object characteristic)) {
          return _cccdValue(_subscriptions[characteristic]);
        }
        return _read(descriptor.key);
      });

  @override
  Future<void> writeDescriptor(
    DiscoveredDescriptor descriptor,
    Uint8List value,
  ) => _request('writeDescriptor', () async {
    if (descriptor.key case (_cccd, final Object characteristic)) {
      return _subscribe(characteristic, _modeOf(value));
    }
    return _write(descriptor.key, value, withResponse: true);
  });

  @override
  Future<int> readRssi() => _request('readRssi', () async => _peripheral.rssi);

  @override
  Future<int> requestMtu(int mtu) => _request('requestMtu', () async {
    if (!_bluetooth.capabilities.requestMtu) return _mtu;
    final next = mtu.clamp(_defaultMtu, _peripheral.maxMtu);
    if (next != _mtu) _updates.add(MtuUpdate(_mtu = next));
    return _mtu;
  });

  @override
  int maximumWriteLength({required bool withResponse}) =>
      withResponse ? LocalAttribute.maxLength : _mtu - 3;

  @override
  Future<void> requestConnectionPriority(ConnectionPriority priority) =>
      _request('requestConnectionPriority', () async => _priority = priority);

  @override
  Future<PhyInfo> setPreferredPhy(Set<Phy> tx, Set<Phy> rx, PhyCoding coding) =>
      _request('setPreferredPhy', () async {
        final next = PhyInfo(tx: _fastest(tx), rx: _fastest(rx));
        if (next != _phy) _updates.add(PhyUpdate(_phy = next));
        return next;
      });

  @override
  Future<PhyInfo> readPhy() => _request('readPhy', () async => _phy);

  @override
  Future<bool> clearGattCache() => _request('clearGattCache', () async {
    _peripheral.cacheClears++;
    return true;
  });

  @override
  Future<L2capChannelBackend> openL2capChannel(
    int psm, {
    required bool secure,
  }) => throw const UnsupportedFeatureException(
    'l2cap',
    'FakeBluetooth does not simulate L2CAP channels',
  );

  void _push(Object key, Uint8List value) {
    if (_state == BluetoothConnectionState.connected) {
      _notifications.add((key: key, value: value));
    }
  }

  void _servicesChanged() {
    if (_state == BluetoothConnectionState.connected) {
      _updates.add(const ServicesUpdate());
    }
  }

  /// Answers a request the way [FakeBluetooth]'s script says, or with
  /// [answer].
  Future<T> _request<T>(String operation, Future<T> Function() answer) async {
    if (_state != BluetoothConnectionState.connected) {
      throw const DisconnectedException();
    }
    switch (_bluetooth._nextScripted()) {
      case final GattError error:
        throw GattException(error, operation);
      case _Unanswered():
        final never = Completer<T>();
        _unanswered.add(never);
        return never.future;
    }
    await _peripheral._ready;
    return answer();
  }

  List<DiscoveredService> _discovery() => [
    for (final service in _peripheral.services)
      DiscoveredService(
        service.uuid,
        service.isPrimary,
        service,
        [
          for (final c in service.characteristics)
            DiscoveredCharacteristic(
              c.uuid,
              c.properties.bits,
              _server.keys[c]!,
              [
                for (final d in c.descriptors)
                  DiscoveredDescriptor(d.uuid, _server.keys[d]!, null),
                if (c.canNotify)
                  DiscoveredDescriptor(
                    BluetoothUuid.clientCharacteristicConfiguration,
                    (_cccd, _server.keys[c]!),
                    null,
                  ),
              ],
              null,
            ),
        ],
        null,
        included: service.includedServices,
      ),
  ];

  Future<Uint8List> _read(Object key) {
    final response = Completer<Uint8List>();
    _server.emit(
      ReadRequested(
        _central,
        key,
        0,
        (error, [value]) => error != null
            ? response.completeError(_failed(error, 'read'))
            : response.complete(value ?? Uint8List(0)),
      ),
    );
    return response.future;
  }

  /// A write without response completes once applied and never fails.
  Future<void> _write(
    Object key,
    Uint8List value, {
    required bool withResponse,
  }) {
    final response = Completer<void>();
    _server.emit(
      WriteRequested(
        _central,
        [(key: key, offset: 0, value: value)],
        (error, [_]) => error != null && withResponse
            ? response.completeError(_failed(error, 'write'))
            : response.complete(),
        withResponse: withResponse,
      ),
    );
    return response.future;
  }

  void _subscribe(Object key, NotifyMode? mode) {
    if (mode == null) {
      _subscriptions.remove(key);
    } else {
      _subscriptions[key] = mode;
    }
    _server.emit(SubscriptionChanged(_central, key, subscribed: mode != null));
  }

  void _setState(BluetoothConnectionState state) {
    if (_state == state) return;
    _state = state;
    _states.add(state);
  }

  static const _cccd = #clientCharacteristicConfiguration;

  static Uint8List _cccdValue(NotifyMode? mode) => Uint8List.fromList([
    switch (mode) {
      NotifyMode.notification => 0x01,
      NotifyMode.indication => 0x02,
      _ => 0x00,
    },
    0x00,
  ]);

  static NotifyMode? _modeOf(Uint8List value) => switch (value.firstOrNull) {
    final bits? when bits & 0x01 != 0 => NotifyMode.notification,
    final bits? when bits & 0x02 != 0 => NotifyMode.indication,
    _ => null,
  };

  static Phy _fastest(Set<Phy> phys) =>
      [Phy.le2M, Phy.le1M, Phy.leCoded].firstWhere(phys.contains);

  static GattException _failed(GattError error, String operation) =>
      GattException(error, operation, nativeCode: error.code);
}

/// This device, as the fake peripheral's server sees it.
final class _AppCentral implements Central {
  _AppCentral(this._link);

  final _FakeLink _link;

  @override
  String get id => 'app';

  @override
  int get maximumUpdateLength => _link.mtu - 3;

  @override
  CentralHandle get native => _noNative();
}
