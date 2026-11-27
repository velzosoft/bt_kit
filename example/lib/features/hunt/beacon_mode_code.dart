import '../../widgets/code_sheet.dart';

const beaconModeCode = CodeSample(
  title: 'Beacon mode: advertising',
  layer2: r'''
final bt = BtKit.instance;
await bt.requestPermissions(BtKit.peripheralPermissions);
final capabilities = bt.capabilities;
if (!capabilities.peripheralRole) return;

final code = 'K7QD';
final advertising = await bt.startAdvertising(
  AdvertiseOptions(
    // iOS: only a local name and service UUIDs.
    localName: capabilities.advertiseLocalName ? 'Radar $code' : null,
    serviceUuids: capabilities.advertiseCustomData ? [] : [beacon],
    // Android: no custom name, but service data. 31 bytes
    // hold the 128-bit service data or the UUID, not both.
    serviceData: capabilities.advertiseCustomData
        ? {beacon: ascii.encode(code)}
        : {},
    mode: AdvertiseMode.lowLatency, // Android only
    txPower: AdvertiseTxPower.high, // Android only
  ),
);

// When the screen closes:
await advertising.stop();
''',
  android: r'''
final advertiser = manager.adapter!.bluetoothLeAdvertiser!;

final parameters = (AdvertisingSetParameters$Builder()
      ..setLegacyMode(true)
      ..setConnectable(true)
      ..setScannable(true)
      ..setInterval(AdvertisingSetParameters.INTERVAL_LOW)
      ..setTxPowerLevel(AdvertisingSetParameters.TX_POWER_HIGH))
    .build()!;
final data = (AdvertiseData$Builder()
      ..addServiceData(
        ParcelUuid.fromString(beacon.toJString())!,
        JByteArray.of(ascii.encode(code)),
      ))
    .build()!;

final callback = AdvertisingSetCallback.implement(
  onAdvertisingSetStarted: (set, txPower, status) {
    if (status != AdvertisingSetCallback.ADVERTISE_SUCCESS) {
      print('Advertising failed: $status');
    }
  },
  onAdvertisingSetStopped: (set) {},
);
advertiser.startAdvertisingSet(
  parameters, data, null, null, null, callback,
);

// Later:
advertiser.stopAdvertisingSet(callback);
''',
  ios: r'''
final delegate = CBPeripheralManagerDelegate.implement(
  peripheralManagerDidUpdateState_: (manager) {
    if (manager.state != CBManagerState.CBManagerStatePoweredOn) return;
    manager.startAdvertising(
      <Object, Object>{
        CBAdvertisementDataLocalNameKey: 'Radar $code',
        CBAdvertisementDataServiceUUIDsKey: [
          CBUUID.UUIDWithString(beacon.toNSString()),
        ],
      }.toNSDictionary(),
    );
  },
  peripheralManagerDidStartAdvertising_error_: (manager, error) {
    if (error != null) print(error.localizedDescription);
  },
);

final manager = CBPeripheralManager.alloc().initWithDelegate$1(
  delegate,
  options: {CBPeripheralManagerOptionShowPowerAlertKey: false}
      .toNSDictionary(),
);

// iOS advertises only while the app is in the foreground.
// Later:
manager.stopAdvertising();
''',
);
