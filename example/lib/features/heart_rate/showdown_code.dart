import '../../widgets/code_sheet.dart';

const showdownCode = CodeSample(
  title: 'Heart-rate showdown: several live connections',
  layer2: r'''
final heartRate = BluetoothUuid.short(0x180d);
final measurement = BluetoothUuid.short(0x2a37);
final batteryService = BluetoothUuid.short(0x180f);
final batteryLevel = BluetoothUuid.short(0x2a19);

// Filter the app's one shared scan in Dart. A second scan with
// other options would throw ScanException.
final straps = scanner.devices
    .where((d) => d.data.serviceUuids.contains(heartRate))
    .map((d) => d.peripheral);

int bpmOf(Uint8List value) =>
    value[0] & 0x01 == 0 ? value[1] : value[1] | value[2] << 8;

// Reconnecting is an app-level loop around connect().
Future<void> keepConnected(Peripheral strap, CancelToken token) async {
  const backoff = [1, 2, 5, 10]; // seconds; the last one repeats
  var attempt = 0;
  int? battery;
  while (!token.isCancelled) {
    try {
      await strap.connect(cancelToken: token);
      await strap.discoverServices(cancelToken: token);

      final level = strap.characteristic(batteryService, batteryLevel);
      if (battery == null && level != null) {
        battery = (await level.read(cancelToken: token)).first;
      }

      final hr = strap.characteristic(heartRate, measurement)!;
      // Ends with DisconnectedException when the strap drops.
      await for (final value in hr.subscribe()) {
        attempt = 0;
        print('${strap.id}: ${bpmOf(value)} BPM');
      }
    } on BluetoothException catch (e) {
      print('Reconnecting: ${e.message}');
      await strap.disconnect();
    }
    if (token.isCancelled) break;
    final seconds = backoff[min(attempt++, backoff.length - 1)];
    await Future<void>.delayed(Duration(seconds: seconds));
  }
}

// Each strap has its own queue, so six loops run side by side.
final token = CancelToken();
unawaited(keepConnected(strap, token));

// Remove the player:
token.cancel();
await strap.disconnect();
''',
  android: r'''
// What bt_kit runs for each strap. Each request waits for its
// callback before the next starts: Android allows one at a time.
UUID uuid(String short) =>
    UUID.fromString('0000$short-0000-1000-8000-00805f9b34fb'.toJString())!;
Uint8List bytesOf(JByteArray value) =>
    Uint8List.sublistView(value.getRange(0, value.length));

final device = adapter.getRemoteDevice$1(address.toJString())!;

late final BluetoothGatt gatt;
final callback = BluetoothGattCallback.implement(
  onConnectionStateChange: (_, status, newState) {
    if (newState == BluetoothProfile.STATE_CONNECTED) {
      gatt.discoverServices();
    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
      gatt.close(); // Android frees nothing by itself.
      // Reconnect: a fresh connectGatt$3 after 1, 2, 5, then 10 s.
    }
  },
  onServicesDiscovered: (_, status) {
    final battery =
        gatt.getService(uuid('180f'))?.getCharacteristic(uuid('2a19'));
    if (battery != null) gatt.readCharacteristic(battery);
  },
  onCharacteristicRead: (_, characteristic, value, status) {
    print('Battery ${bytesOf(value!).first}%');

    final hr = gatt.getService(uuid('180d'))!.getCharacteristic(uuid('2a37'))!;
    gatt.setCharacteristicNotification(hr, true);
    gatt.writeDescriptor(
      hr.getDescriptor(uuid('2902'))!,
      BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE!,
    );
  },
  onCharacteristicChanged: (_, characteristic, value) {
    final bytes = bytesOf(value!);
    final bpm = bytes[0] & 0x01 == 0 ? bytes[1] : bytes[1] | bytes[2] << 8;
    print('$bpm BPM');
  },
);

gatt = device.connectGatt$3(
  context,
  false, // autoConnect off: the app runs its own reconnect loop
  callback,
  BluetoothDevice.TRANSPORT_LE,
  BluetoothDevice.PHY_LE_1M_MASK,
)!;

// Remove the player:
gatt.disconnect(); // close() follows in onConnectionStateChange
''',
  ios: r'''
// What bt_kit runs for each strap. `peripheral` comes from
// centralManager:didDiscoverPeripheral: in the shared scan.
String uuidOf(CBAttribute attribute) =>
    attribute.UUID.UUIDString.toDartString();

final peripheralDelegate = CBPeripheralDelegate.implement(
  peripheral_didDiscoverServices_: (peripheral, error) {
    for (final service in peripheral.services!.asDart()) {
      peripheral.discoverCharacteristics(
        null,
        forService: CBService.as(service),
      );
    }
  },
  // bt_kit also runs discoverDescriptorsForCharacteristic on each one
  // before discoverServices() completes.
  peripheral_didDiscoverCharacteristicsForService_error_:
      (peripheral, service, error) {
    for (final item in service.characteristics!.asDart()) {
      final characteristic = CBCharacteristic.as(item);
      switch (uuidOf(characteristic)) {
        case '2A19': // Battery Level, read once
          peripheral.readValueForCharacteristic(characteristic);
        case '2A37': // Heart Rate Measurement
          peripheral.setNotifyValue(true, forCharacteristic: characteristic);
      }
    }
  },
  // Reads and notifications both arrive here.
  peripheral_didUpdateValueForCharacteristic_error_:
      (peripheral, characteristic, error) {
    final bytes = characteristic.value!.toList();
    if (uuidOf(characteristic) == '2A37') {
      final bpm = bytes[0] & 0x01 == 0 ? bytes[1] : bytes[1] | bytes[2] << 8;
      print('$bpm BPM');
    }
  },
);

final delegate = CBCentralManagerDelegate.implement(
  centralManager_didConnectPeripheral_: (central, peripheral) {
    peripheral.discoverServices(null);
  },
  centralManager_didDisconnectPeripheral_error_:
      (central, peripheral, error) {
    // Reconnect after 1, 2, 5, then 10 s.
    Timer(delay, () => central.connectPeripheral(peripheral));
  },
);
final central = CBCentralManager.alloc()
    .initWithDelegate(delegate, queue: null);

// Delegate properties are weak: keep peripheralDelegate referenced.
peripheral.delegate = peripheralDelegate;
central.connectPeripheral(peripheral); // no auto-reconnect option

// Remove the player:
central.cancelPeripheralConnection(peripheral);
''',
);
