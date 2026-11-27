import '../../widgets/code_sheet.dart';

const boardCode = CodeSample(
  title: 'Hello board: one scan, one connection, two subscriptions, one write',
  layer2: r'''
final board = AppUuids.board; // f3b1a030-6b2c-4e7a-9a54-7c2d8e0b1a00

// Filter the app's one shared scan in Dart; no second scan.
final device = scanner.devices
    .firstWhere((d) => d.data.serviceUuids.contains(board))
    .peripheral;

await device.connect();
if (BtKit.instance.capabilities.connectionPriority) {
  // Android: a short connection interval. The board asks iOS for 15 ms.
  await device.requestConnectionPriority(ConnectionPriority.high);
}
await device.discoverServices();

// The LED first, then the button, so the app sees the board turn green.
device.characteristic(board, AppUuids.boardLed)!
    .subscribe()
    .listen((value) => led.value = LedState.parse(value));

device.characteristic(board, AppUuids.boardButton)!
    .subscribe()
    .listen((value) {
      final event = ButtonEvent.parse(value)!;
      // The circle grows from the phone's clock; the board sends only
      // the press and the release, with the exact hold time.
      event.pressed ? circle.grow() : circle.pop(event.held);
    });

// 01 rr gg bb nn: flash nn times. A refused write throws GattException.
await device.characteristic(board, AppUuids.boardLedCommand)!
    .write(BlinkCommand(color, count: 3).encode());

// Leaving the screen; the board goes back to blinking blue.
await device.disconnect();
''',
  android: r'''
// What bt_kit runs on Android. Each request waits for its callback
// before the next starts: Android allows one at a time.
UUID uuid(String id) => UUID.fromString(
  'f3b1a$id-6b2c-4e7a-9a54-7c2d8e0b1a00'.toJString(),
)!;
final cccdUuid =
    UUID.fromString('00002902-0000-1000-8000-00805f9b34fb'.toJString())!;

late final BluetoothGatt gatt;
BluetoothGattCharacteristic board(String id) =>
    gatt.getService(uuid('030'))!.getCharacteristic(uuid(id))!;

void enableNotifications(BluetoothGattCharacteristic characteristic) {
  gatt.setCharacteristicNotification(characteristic, true); // local switch
  gatt.writeDescriptor(
    characteristic.getDescriptor(cccdUuid)!, // and the board's CCCD
    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE!,
  );
}

final callback = BluetoothGattCallback.implement(
  onConnectionStateChange: (_, status, newState) {
    if (newState == BluetoothProfile.STATE_CONNECTED) {
      gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
      gatt.discoverServices();
    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
      gatt.close();
    }
  },
  onServicesDiscovered: (_, status) => enableNotifications(board('033')),
  onDescriptorWrite: (_, descriptor, status) {
    if (descriptor!.characteristic!.uuid == uuid('033')) {
      enableNotifications(board('031')); // the LED turns green now
    }
  },
  onCharacteristicChanged: (_, characteristic, value) {
    final bytes = value!.getRange(0, value.length);
    print('${characteristic!.uuid}: $bytes');
  },
  onCharacteristicWrite: (_, characteristic, status) =>
      print(status == BluetoothGatt.GATT_SUCCESS ? 'blinking' : 'refused'),
);

gatt = device.connectGatt$3(
  context,
  false,
  callback,
  BluetoothDevice.TRANSPORT_LE,
  BluetoothDevice.PHY_LE_1M_MASK,
)!;

// Blink: 3 white flashes, with a response.
gatt.writeCharacteristic(
  board('032'),
  JByteArray.of([0x01, 0xff, 0xff, 0xff, 0x03]),
  BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
);
''',
  ios: r'''
// What bt_kit runs on iOS. `central` and `peripheral` come from the
// shared scan; centralManager:didConnectPeripheral: calls
// peripheral.discoverServices(null).
String uuidOf(CBAttribute attribute) =>
    attribute.UUID.UUIDString.toDartString().toLowerCase();
final characteristics = <String, CBCharacteristic>{};

final delegate = CBPeripheralDelegate.implement(
  peripheral_didDiscoverServices_: (peripheral, error) {
    for (final service in peripheral.services!.asDart()) {
      peripheral.discoverCharacteristics(
        null,
        forService: CBService.as(service),
      );
    }
  },
  peripheral_didDiscoverCharacteristicsForService_error_:
      (peripheral, service, error) {
    for (final item in service.characteristics!.asDart()) {
      final characteristic = CBCharacteristic.as(item);
      characteristics[uuidOf(characteristic).substring(5, 8)] =
          characteristic;
    }
    // iOS writes the CCCD itself. The LED first, then the button.
    peripheral.setNotifyValue(true, forCharacteristic: characteristics['033']!);
  },
  peripheral_didUpdateNotificationStateForCharacteristic_error_:
      (peripheral, characteristic, error) {
    if (characteristic == characteristics['033']) {
      peripheral.setNotifyValue(
        true,
        forCharacteristic: characteristics['031']!,
      );
    }
  },
  peripheral_didUpdateValueForCharacteristic_error_:
      (peripheral, characteristic, error) =>
          print('${uuidOf(characteristic)}: ${characteristic.value?.toList()}'),
  peripheral_didWriteValueForCharacteristic_error_:
      (peripheral, characteristic, error) =>
          print(error == null ? 'blinking' : 'refused'),
);
peripheral.delegate = delegate; // Weak: keep `delegate` alive.
central.connectPeripheral(peripheral);

// Blink: 3 white flashes, with a response.
peripheral.writeValue(
  [0x01, 0xff, 0xff, 0xff, 0x03].toNSData(),
  forCharacteristic: characteristics['032']!,
  type: CBCharacteristicWriteType.CBCharacteristicWriteWithResponse,
);
''',
);
