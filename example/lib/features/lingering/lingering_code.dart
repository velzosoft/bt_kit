import '../../widgets/code_sheet.dart';

const lingeringCode = CodeSample(
  title: 'Stayed with you: the shared scan as snapshots',
  layer2: r'''
// The app's one shared scan, as the list of devices heard in the last
// 15 s. bt_kit drops a device once it has been silent that long.
const options = ScanOptions(
  allowDuplicates: true,
  mode: ScanMode.lowLatency,
);
var around = <String>{};
final subscription = BtKit.instance
    .scanDevices(options, expireAfter: const Duration(seconds: 15))
    .listen((list) => around = {for (final ad in list) ad.peripheral.id});

// Every 15 s, the devices around form a snapshot. When 80% of the other
// devices have been replaced, the surroundings changed; a device present
// on both sides stayed with you.
final detector = StayDetector();
final timer = Timer.periodic(const Duration(seconds: 15), (_) {
  detector.addSnapshot(DateTime.now(), around);
  for (final device in detector.flagged) {
    print('${device.id} stayed through ${device.stays} changes');
  }
});

// When the screen closes, everything is forgotten:
timer.cancel();
await subscription.cancel();
''',
  android: r'''
final context = androidApplicationContext.as(Context.type);
final manager = context
    .getSystemService$1(Context.BLUETOOTH_SERVICE!)!
    .as(BluetoothManager.type);
final scanner = manager.adapter!.bluetoothLeScanner!;
final lastHeard = <String, DateTime>{};

final callback = ScanCallback.implement(
  onScanResult: (callbackType, result) {
    // Phones and many trackers rotate this address: a new address
    // looks like a new device.
    final address = result!.device!.address!.toDartString();
    lastHeard[address] = DateTime.now();
  },
);

final settings = (ScanSettings$Builder()
      ..setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY))
    .build()!;
scanner.startScan$2(<ScanFilter?>[].toJList(), settings, callback);

// Later:
scanner.stopScan$1(callback);
''',
  ios: r'''
final lastHeard = <String, DateTime>{};

final delegate = CBCentralManagerDelegate.implement(
  centralManagerDidUpdateState_: (central) {
    if (central.state != CBManagerState.CBManagerStatePoweredOn) return;
    central.scanForPeripheralsWithServices(
      null,
      options: {CBCentralManagerScanOptionAllowDuplicatesKey: true}
          .toNSDictionary(),
    );
  },
  centralManager_didDiscoverPeripheral_advertisementData_RSSI_:
      (central, peripheral, advertisementData, rssi) {
    // A per-app id. iOS never reports some Apple advertisements.
    final id = peripheral.identifier.UUIDString.toDartString();
    lastHeard[id] = DateTime.now();
  },
);

final central = CBCentralManager.alloc()
    .initWithDelegate(delegate, queue: null);

// Later:
central.stopScan();
''',
);
