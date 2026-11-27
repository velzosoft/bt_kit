import '../../widgets/code_sheet.dart';

const explorerCode = CodeSample(
  title: 'Explorer: connect, read, write, subscribe',
  layer2: r'''
final device = advertisement.peripheral;
final cancel = CancelToken(); // The Cancel button calls cancel.cancel().

device.connectionStates.listen(print); // connecting, connected, ...
await device.connect(cancelToken: cancel);
final services = await device.discoverServices(cancelToken: cancel);

for (final service in services) {
  for (final characteristic in service.characteristics) {
    final p = characteristic.properties;
    print('${service.uuid} ${characteristic.uuid} '
        'read: ${p.read} write: ${p.write} notify: ${p.notify}');
  }
}

final battery = device.characteristic(
  BluetoothUuid.short(0x180f),
  BluetoothUuid.short(0x2a19),
)!;
final level = await battery.read(); // [87]: 87 %
for (final descriptor in battery.descriptors) {
  print('${descriptor.uuid}: ${await descriptor.read()}');
}

final characteristic = device.characteristic(serviceUuid, uuid)!;
final limit = device.maximumWriteLength(withResponse: false);
await characteristic.write([0x01, 0xff], withResponse: false);

final subscription = characteristic.subscribe().listen(
  (value) => print(value),
  onError: (Object e) => print(e), // DisconnectedException on a drop
);

final rssi = await device.readRssi();
final mtu = await device.requestMtu(517); // iOS negotiates by itself
device.mtuChanges.listen(print); // Android 14+ reports 517 unprompted
await device.requestConnectionPriority(ConnectionPriority.high); // Android
print(characteristic.lastValue); // the last value read, written or pushed

// The device changed its database: stale attributes now fail.
device.servicesChanged.listen((_) => device.discoverServices());

try {
  await characteristic.write([0x01]);
} on BluetoothException catch (e) {
  switch (e) {
    case GattException(:final error):
      print('Refused: ${error.name}');
    case OperationTimeoutException():
      print('No answer');
    case DisconnectedException(:final reason):
      print('Link lost: ${reason?.cause}'); // remote, linkLoss, ...
    default:
      print(e.message);
  }
}

// Layer 1 inside Layer 2, with package:bt_kit/android.dart, for what
// Layer 2 does not wrap, such as Android 15's digital car key priority.
// exclusive() holds the queue so no Layer 2 call overlaps.
await device.exclusive(() async {
  device.native.android?.gatt?.requestConnectionPriority(
    BluetoothGatt.CONNECTION_PRIORITY_DCK,
  );
});

// Leaving the screen:
await subscription.cancel();
await device.disconnect();
''',
  android: r'''
final context = androidApplicationContext.as(Context.type);
final adapter = context
    .getSystemService$1(Context.BLUETOOTH_SERVICE!)!
    .as(BluetoothManager.type)
    .adapter!;
final device = adapter.getRemoteDevice$1(address.toJString())!; // From the scan

final callback = BluetoothGattCallback.implement(
  onConnectionStateChange: (gatt, status, newState) {
    if (newState == BluetoothProfile.STATE_CONNECTED) {
      gatt!.discoverServices();
    }
  },
  onServicesDiscovered: (gatt, status) {
    for (final service in gatt!.services!.asDart().nonNulls) {
      for (final c in service.characteristics!.asDart().nonNulls) {
        print('${service.uuid} ${c.uuid} properties: ${c.properties}');
      }
    }
  },
  onCharacteristicRead: (gatt, characteristic, value, status) =>
      print(value!.getRange(0, value.length)),
  onCharacteristicWrite: (gatt, characteristic, status) =>
      print(status == BluetoothGatt.GATT_SUCCESS),
  onCharacteristicChanged: (gatt, characteristic, value) =>
      print(value!.getRange(0, value.length)),
  onDescriptorWrite: (gatt, descriptor, status) => print('CCCD $status'),
  onReadRemoteRssi: (gatt, rssi, status) => print('$rssi dBm'),
  onMtuChanged: (gatt, mtu, status) => print('MTU $mtu'),
);

final gatt = device.connectGatt$3(
  context,
  false, // autoConnect
  callback,
  BluetoothDevice.TRANSPORT_LE,
  BluetoothDevice.PHY_LE_1M_MASK,
)!;

// One request at a time: wait for its callback before the next.
gatt.readCharacteristic(characteristic);

gatt.writeCharacteristic(
  characteristic,
  JByteArray.of([0x01, 0xff]),
  BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
);

// Notifications: a local switch, plus a write to the CCCD (0x2902).
gatt.setCharacteristicNotification(characteristic, true);
final cccd = characteristic.getDescriptor(
  UUID.fromString('00002902-0000-1000-8000-00805f9b34fb'.toJString()),
)!;
gatt.writeDescriptor(
  cccd,
  BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE!,
);

gatt.readRemoteRssi();
gatt.requestMtu(517);
gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);

// Leaving the screen: disconnect, then close once disconnected.
gatt.disconnect();
gatt.close();
''',
  ios: r'''
// `central` and `peripheral` come from the Radar sample's scan. Its
// central delegate also implements:
//   centralManager_didConnectPeripheral_: (central, peripheral) =>
//       peripheral.discoverServices(null),

final delegate = CBPeripheralDelegate.implement(
  peripheral_didDiscoverServices_: (peripheral, error) {
    for (final s in peripheral.services!.asDart()) {
      peripheral.discoverCharacteristics(null, forService: CBService.as(s));
    }
  },
  peripheral_didDiscoverCharacteristicsForService_error_:
      (peripheral, service, error) {
    for (final c in service.characteristics!.asDart()) {
      final characteristic = CBCharacteristic.as(c);
      print('${characteristic.UUID.UUIDString.toDartString()} '
          'properties: ${characteristic.properties}');
      peripheral.discoverDescriptorsForCharacteristic(characteristic);
    }
  },
  // Read results and notifications both arrive here.
  peripheral_didUpdateValueForCharacteristic_error_:
      (peripheral, characteristic, error) =>
          print(characteristic.value?.toList()),
  peripheral_didWriteValueForCharacteristic_error_:
      (peripheral, characteristic, error) => print('written: $error'),
  peripheral_didUpdateNotificationStateForCharacteristic_error_:
      (peripheral, characteristic, error) =>
          print('notifying: ${characteristic.isNotifying}'),
  peripheral_didReadRSSI_error_: (peripheral, rssi, error) =>
      print('${rssi.intValue} dBm'),
);
peripheral.delegate = delegate; // Weak: keep `delegate` alive.

central.connectPeripheral(peripheral);

peripheral.readValueForCharacteristic(characteristic);

final limit = peripheral.maximumWriteValueLengthForType(
  CBCharacteristicWriteType.CBCharacteristicWriteWithoutResponse,
);
peripheral.writeValue(
  [0x01, 0xff].toNSData(),
  forCharacteristic: characteristic,
  type: CBCharacteristicWriteType.CBCharacteristicWriteWithResponse,
);

// iOS writes the CCCD itself; writing it directly raises an exception.
peripheral.setNotifyValue(true, forCharacteristic: characteristic);

peripheral.readRSSI(); // The MTU is negotiated by iOS.

// Leaving the screen:
central.cancelPeripheralConnection(peripheral);
''',
);
