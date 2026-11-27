part of 'fake_bluetooth.dart';

final class _FakeCentral implements CentralBackend {
  _FakeCentral(this._bluetooth);

  final FakeBluetooth _bluetooth;

  @override
  AdapterHandle get native => _noNative();

  @override
  BluetoothCapabilities get capabilities => _bluetooth.capabilities;

  @override
  late final PeripheralRoleBackend peripheralRole = _FakePeripheralRole(
    _bluetooth,
  );

  static const _notSimulated = 'FakeBluetooth does not simulate it';

  @override
  final ClassicBackend classic = const UnsupportedClassic(_notSimulated);

  @override
  final AccessoryBackend accessories = const UnsupportedAccessories(
    _notSimulated,
  );

  @override
  final CompanionBackend companion = const UnsupportedCompanion(_notSimulated);

  @override
  final BackgroundBackend background = const UnsupportedBackground(
    _notSimulated,
  );

  @override
  final AudioBackend audio = const UnsupportedAudio(_notSimulated);

  @override
  AdapterState get adapterState => _bluetooth.adapterState;

  @override
  Set<BluetoothPermission> get scanPermissions => const {
    BluetoothPermission.scan,
  };

  @override
  Future<String?> adapterName() async => _bluetooth.adapterName;

  @override
  Stream<AdapterState> get adapterStates => _bluetooth._states.stream;

  @override
  Future<AdapterState> settledAdapterState() async => adapterState;

  @override
  Future<Map<BluetoothPermission, PermissionStatus>> checkPermissions(
    Set<BluetoothPermission> permissions,
  ) async => {
    for (final permission in permissions)
      permission:
          _bluetooth.permissions[permission] ?? PermissionStatus.granted,
  };

  @override
  Future<Map<BluetoothPermission, PermissionStatus>> requestPermissions(
    Set<BluetoothPermission> permissions,
  ) async {
    for (final permission in permissions) {
      final status = _bluetooth.permissions[permission];
      if (status == PermissionStatus.notDetermined ||
          status == PermissionStatus.denied) {
        _bluetooth.permissions[permission] = _bluetooth.requestAnswer;
      }
    }
    return checkPermissions(permissions);
  }

  @override
  Future<bool> requestEnable() async {
    _bluetooth.adapterState = AdapterState.poweredOn;
    return true;
  }

  @override
  Stream<ScanHit> scan(ScanOptions options) {
    late final StreamController<ScanHit> controller;
    controller = StreamController<ScanHit>(
      onListen: () {
        _bluetooth._scans.add(controller);
        scheduleMicrotask(() {
          for (final peripheral in _bluetooth._peripherals.values) {
            _bluetooth._deliver(controller, peripheral);
          }
        });
      },
      onCancel: () => _bluetooth._scans.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<PeripheralBackend?> peripheral(String id) async =>
      _bluetooth._peripherals[id]?._link;

  @override
  Future<List<PeripheralBackend>> systemPeripherals(
    List<BluetoothUuid> services,
  ) async => [
    for (final peripheral in _bluetooth._peripherals.values)
      if (peripheral.isConnected &&
          (services.isEmpty ||
              peripheral.services.any((s) => services.contains(s.uuid))))
        peripheral._link,
  ];

  @override
  Future<List<PeripheralBackend>> bondedPeripherals() async => [
    for (final peripheral in _bluetooth._peripherals.values)
      if (peripheral.bondState == BondState.bonded) peripheral._link,
  ];

  @override
  Future<void> openBluetoothSettings() async => _bluetooth.settingsOpened++;

  @override
  Stream<SystemConnectionEvent> systemConnections(
    List<BluetoothUuid> services,
    List<String> peripheralIds,
  ) => const Stream.empty();

  @override
  Stream<CentralRestoration> get restorations => const Stream.empty();
}

final class _FakePeripheralRole implements PeripheralRoleBackend {
  _FakePeripheralRole(this._bluetooth);

  final FakeBluetooth _bluetooth;

  static const _unsupported = UnsupportedFeatureException(
    'peripheralRole',
    'FakeBluetooth does not simulate the peripheral role',
  );

  @override
  Future<AdapterState> settledState() async => _bluetooth.adapterState;

  @override
  Future<ServerBackend> openServer() => throw _unsupported;

  @override
  Future<AdvertisingBackend> startAdvertising(AdvertiseOptions options) =>
      throw _unsupported;

  @override
  Future<L2capServerBackend> publishL2cap({required bool secure}) =>
      throw _unsupported;

  @override
  Stream<PeripheralRoleRestoration> get restorations => const Stream.empty();
}
