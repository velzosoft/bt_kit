import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/central/bt_kit.dart' show installBackend;
import 'package:bt_kit/src/platform/accessory_backend.dart';
import 'package:bt_kit/src/platform/audio_backend.dart';
import 'package:bt_kit/src/platform/background_backend.dart';
import 'package:bt_kit/src/platform/bond_backend.dart';
import 'package:bt_kit/src/platform/central_backend.dart';
import 'package:bt_kit/src/platform/classic_backend.dart';
import 'package:bt_kit/src/platform/companion_backend.dart';
import 'package:bt_kit/src/platform/peripheral_role_backend.dart';
import 'package:bt_kit/src/platform/unsupported.dart';

import 'capabilities.dart' as fakes;

/// A central backend for `BtKit`-level tests: each feature is a small
/// recorder, and anything else is unimplemented.
final class TestCentral implements CentralBackend {
  TestCentral() {
    installBackend(this);
  }

  static void uninstall() => installBackend(null);

  @override
  BluetoothCapabilities capabilities = fakes.capabilities();

  final denied = <BluetoothPermission>{};
  final peripherals = <String, TestPeripheral>{};
  final connectionEvents = StreamController<SystemConnectionEvent>.broadcast();
  final _restorations = StreamController<CentralRestoration>.broadcast();
  CentralRestoration? _restored;

  @override
  final TestBackground background = TestBackground();

  @override
  final TestAudio audio = TestAudio();

  @override
  final TestRole peripheralRole = TestRole();

  @override
  final ClassicBackend classic = const UnsupportedClassic('test');

  @override
  final AccessoryBackend accessories = const UnsupportedAccessories('test');

  @override
  final CompanionBackend companion = const UnsupportedCompanion('test');

  TestPeripheral add(String id) => peripherals[id] = TestPeripheral(id);

  void restore(List<TestPeripheral> restored, List<BluetoothUuid> services) {
    final restoration = _restored = (
      peripherals: restored,
      scanServices: services,
    );
    _restorations.add(restoration);
  }

  /// What `scanPermissions` reports; Android adds location when the
  /// manifest does not disavow it.
  Set<BluetoothPermission> scanNeeds = {BluetoothPermission.scan};

  String? name = 'Test adapter';

  @override
  AdapterState get adapterState => AdapterState.poweredOn;

  @override
  Set<BluetoothPermission> get scanPermissions => scanNeeds;

  @override
  Future<String?> adapterName() async => name;

  @override
  Stream<AdapterState> get adapterStates => const Stream.empty();

  @override
  Future<AdapterState> settledAdapterState() async => adapterState;

  @override
  Future<Map<BluetoothPermission, PermissionStatus>> checkPermissions(
    Set<BluetoothPermission> permissions,
  ) async => {
    for (final permission in permissions)
      permission: denied.contains(permission)
          ? PermissionStatus.denied
          : PermissionStatus.granted,
  };

  @override
  Future<PeripheralBackend?> peripheral(String id) async => peripherals[id];

  @override
  Stream<SystemConnectionEvent> systemConnections(
    List<BluetoothUuid> services,
    List<String> peripheralIds,
  ) => connectionEvents.stream;

  @override
  Stream<CentralRestoration> get restorations async* {
    if (_restored case final restored?) yield restored;
    yield* _restorations.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class TestPeripheral implements PeripheralBackend {
  TestPeripheral(this.id);

  @override
  final String id;

  @override
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;

  final distances = <(DistanceMethod, MeasurementRate)>[];
  StreamController<DistanceMeasurement>? measuring;

  @override
  String? get name => null;

  @override
  Stream<BluetoothConnectionState> get connectionStates => const Stream.empty();

  @override
  Stream<ValueNotification> get notifications => const Stream.empty();

  @override
  Stream<LinkUpdate> get updates => const Stream.empty();

  @override
  BondBackend get bond => const UnsupportedBond('test');

  @override
  Stream<DistanceMeasurement> measureDistance(
    DistanceMethod method,
    MeasurementRate rate,
  ) {
    distances.add((method, rate));
    return (measuring = StreamController()).stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class TestBackground implements BackgroundBackend {
  final scans = <ScanOptions>[];
  var stopped = 0;
  var handledCount = 0;
  final signalController = StreamController<BackgroundSignal>.broadcast();

  @override
  Future<void> startScan(ScanOptions options) async => scans.add(options);

  @override
  Future<void> stopScan() async => stopped++;

  @override
  Stream<BackgroundSignal> get signals => signalController.stream;

  @override
  void register(int dispatcherHandle, int handlerHandle) {}

  @override
  int? get handlerHandle => null;

  @override
  void acknowledgeEvents() {}

  @override
  void handled() => handledCount++;
}

final class TestAudio implements AudioBackend {
  final connected = <AudioConnection>[];
  final changeController = StreamController<AudioConnection>.broadcast();

  @override
  Future<List<AudioConnection>> connections(Set<AudioProfile> profiles) async =>
      [
        for (final c in connected)
          if (profiles.contains(c.profile)) c,
      ];

  @override
  Stream<AudioConnection> get changes => changeController.stream;
}

final class TestRole implements PeripheralRoleBackend {
  final _restorations = StreamController<PeripheralRoleRestoration>.broadcast();
  final advertisements = <TestAdvertising>[];

  @override
  Future<AdapterState> settledState() async => AdapterState.poweredOn;

  @override
  Future<AdvertisingBackend> startAdvertising(AdvertiseOptions options) async {
    final advertising = TestAdvertising(options);
    advertisements.add(advertising);
    return advertising;
  }

  void restore(List<BluetoothUuid> services, {required bool advertising}) =>
      _restorations.add((services: services, advertising: advertising));

  @override
  Stream<PeripheralRoleRestoration> get restorations => _restorations.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what the advertisement was asked to do.
final class TestAdvertising implements AdvertisingBackend {
  TestAdvertising(this.options);

  AdvertiseOptions options;
  final updates = <AdvertiseOptions>[];
  var stopped = false;
  BluetoothException? failNext;

  @override
  AdvertisingHandle get native => throw UnimplementedError();

  @override
  Future<void> update(AdvertiseOptions options) async {
    if (failNext case final error?) {
      failNext = null;
      throw error;
    }
    updates.add(this.options = options);
  }

  @override
  Future<void> stop() async => stopped = true;
}

/// A scan hit for [peripheral], as the platform would deliver it.
ScanHit hitFor(TestPeripheral peripheral) => (
  peripheral: peripheral,
  rssi: -40,
  data: AdvertisementData(manufacturerData: {0x0059: Uint8List(1)}),
  native: null,
);
