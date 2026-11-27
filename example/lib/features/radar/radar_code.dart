import '../../widgets/code_sheet.dart';

const radarCode = CodeSample(
  title: 'Radar: one shared scan',
  layer2: r'''
final bt = BtKit.instance;
await bt.requestPermissions();

// Every listener with equal options shares one native scan.
const options = ScanOptions(
  allowDuplicates: true,
  mode: ScanMode.lowLatency,
);

// The devices heard in the last 30 s, in the order they were found, at
// most twice a second: the radar's blips.
final devices = bt
    .scanDevices(options, expireAfter: const Duration(seconds: 30))
    .listen((list) => print('${list.length} devices around'));

// Every advertisement, to smooth each device's signal strength:
final subscription = bt.scan(options).listen((ad) {
  if (ad.rssi == 127) return; // iOS: signal strength unknown
  final data = ad.data;
  print('${ad.peripheral.id} ${ad.rssi} dBm');
  print('name: ${data.localName}');
  print('services: ${data.serviceUuids}');
  print('companies: ${data.manufacturerData.keys}');
  print('tx power: ${data.txPowerLevel}');
});

// When the app goes to the background:
await devices.cancel();
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
    final address = result!.device!.address!.toDartString();
    final record = result.scanRecord;
    print('$address ${result.rssi} dBm');
    print('name: ${record?.deviceName?.toDartString()}');
    print('tx power: ${record?.txPowerLevel}');
  },
  onScanFailed: (errorCode) => print('Scan failed: $errorCode'),
);

final settings = (ScanSettings$Builder()
      ..setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY))
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
    final id = peripheral.identifier.UUIDString.toDartString();
    print('$id ${rssi.intValue} dBm'); // 127: unknown
    print(advertisementData[CBAdvertisementDataLocalNameKey]);
  },
);

final central = CBCentralManager.alloc()
    .initWithDelegate(delegate, queue: null);

// Later:
central.stopScan();
''',
);
