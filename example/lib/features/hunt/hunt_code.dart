import '../../widgets/code_sheet.dart';

const huntCode = CodeSample(
  title: 'Hunt: one device on the shared scan',
  layer2: r'''
final bt = BtKit.instance;

// Equal options share the radar's native scan, so the hunt
// neither restarts it nor starts a second one.
const options = ScanOptions(
  allowDuplicates: true,
  mode: ScanMode.lowLatency,
);

// A median of the last 5 readings removes spikes, then an
// exponential moving average (α 0.3) removes jitter.
final filter = RssiFilter();

final subscription = bt
    .scan(options)
    .where((ad) => ad.peripheral.id == target.id)
    .listen((ad) {
      final rssi = filter.add(ad.rssi); // skips iOS's 127
      if (rssi == null) return;
      lastHeard = ad.receivedAt; // "Signal lost" after 5 s
      strength = Signal.strength(rssi); // 0 far … 1 touching
    });

// Each click is scheduled from the current strength:
// 2 s apart when barely heard, 30 ms when touching.
Duration interval(double strength) =>
    const Duration(seconds: 2) * pow(30 / 2000, strength);

// When the app is hidden or the hunt ends:
await subscription.cancel();
''',
  android: r'''
final context = androidApplicationContext.as(Context.type);
final manager = context
    .getSystemService$1(Context.BLUETOOTH_SERVICE!)!
    .as(BluetoothManager.type);
final scanner = manager.adapter!.bluetoothLeScanner!;

final callback = ScanCallback.implement(
  onScanResult: (callbackType, result) {
    // On Android the device id is its address.
    final address = result!.device!.address!.toDartString();
    if (address != targetAddress) return;
    onRssi(result.rssi);
  },
  onScanFailed: (errorCode) => print('Scan failed: $errorCode'),
);

// One scan for the whole app: Android throttles apps that
// start scans more than 5 times in 30 seconds.
final settings = (ScanSettings$Builder()
      ..setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
      ..setLegacy(false))
    .build()!;
scanner.startScan$2(<ScanFilter?>[].toJList(), settings, callback);

// Later:
scanner.stopScan$1(callback);
''',
  ios: r'''
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
    // iOS makes up its own id for each device, per app.
    final id = peripheral.identifier.UUIDString.toDartString();
    if (id != targetId) return;
    if (rssi.intValue == 127) return; // signal strength unknown
    onRssi(rssi.intValue);
  },
);

final central = CBCentralManager.alloc()
    .initWithDelegate(delegate, queue: null);

// Later:
central.stopScan();
''',
);
