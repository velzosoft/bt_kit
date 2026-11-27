import '../../widgets/code_sheet.dart';

const labCode = CodeSample(
  title: 'Lab: both sides of the reference profile',
  layer2: r'''
final bt = BtKit.instance;
final lab = BluetoothUuid.parse('f3b1a100-6b2c-4e7a-9a54-7c2d8e0b1a00');

// Phone A: be the reference peripheral.
await bt.requestPermissions(BtKit.peripheralPermissions);
if (!bt.capabilities.peripheralRole) return;
final stream = LocalCharacteristic(
  streamUuid,
  properties: const CharacteristicProperties.of(notify: true),
);
final control = LocalCharacteristic(
  controlUuid,
  properties: const CharacteristicProperties.of(write: true),
  onWrite: (request) {
    if (request.value.length != 3) {
      throw GattException(GattError.invalidAttributeValueLength, 'write');
    }
    startPump(); // server.notify(stream, packet), 50 times a second
  },
);
final server = await bt.openGattServer(
  services: [LocalService(lab, [stream, control])],
);
await bt.startAdvertising(AdvertiseOptions(serviceUuids: [lab]));
await server.notify(stream, packet); // to every subscribed central

// Phone B: one connection cycle.
final ad = await bt
    .scan(const ScanOptions(allowDuplicates: true, mode: ScanMode.lowLatency))
    .firstWhere((ad) => ad.data.serviceUuids.contains(lab));
final device = ad.peripheral;
await device.connect(timeout: const Duration(seconds: 10));
await device.discoverServices();
final echo = device.characteristic(lab, echoUuid)!;
await echo.write(utf8.encode('cycle 1'));
print(await echo.read());
await device.disconnect();

// Cancellation and timeouts never stall the queue.
final token = CancelToken();
final pending = echo.read(cancelToken: token);
token.cancel(); // pending fails with OperationCancelledException
await echo.read(timeout: const Duration(milliseconds: 5));
// ...or fails with OperationTimeoutException; the next read still runs.

// Layer 1 inside the queue: a short connection interval for the soak.
await device.exclusive(() async {
  device.native.android?.gatt?.requestConnectionPriority(
    BluetoothGatt.CONNECTION_PRIORITY_HIGH,
  );
});
''',
  android: r'''
// openGattServer and addService
late final BluetoothGattServer server;
server = manager.openGattServer(
  context,
  BluetoothGattServerCallback.implement(
    onServiceAdded: (status, service) {/* add the next service */},
    onCharacteristicReadRequest: (device, requestId, offset, characteristic) =>
        server.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS,
            offset, JByteArray.of(value)),
    onCharacteristicWriteRequest: (device, requestId, characteristic,
        prepared, responseNeeded, offset, value) {/* store or reject */},
    onDescriptorWriteRequest: (device, requestId, descriptor, prepared,
        responseNeeded, offset, value) {/* the CCCD: who subscribed */},
    onNotificationSent: (device, status) {/* the next one may go */},
  ),
)!;
final service = BluetoothGattService(
  UUID.fromString(lab.toJString()),
  BluetoothGattService.SERVICE_TYPE_PRIMARY,
)..addCharacteristic(BluetoothGattCharacteristic(
    UUID.fromString(stream.toJString()),
    BluetoothGattCharacteristic.PROPERTY_NOTIFY,
    0,
  ));
server.addService(service);

// startAdvertising
adapter.bluetoothLeAdvertiser!.startAdvertisingSet(
  (AdvertisingSetParameters$Builder()
        ..setLegacyMode(true)
        ..setConnectable(true))
      .build(),
  (AdvertiseData$Builder()
        ..addServiceUuid(ParcelUuid.fromString(lab.toJString())))
      .build(),
  null, null, null,
  AdvertisingSetCallback.implement(
    onAdvertisingSetStarted: (set, txPower, status) {/* started */},
  ),
);

// notify: one per central in flight, until onNotificationSent
server.notifyCharacteristicChanged(
    central, characteristic, false, JByteArray.of(packet));

// Phone B: one connection cycle.
final gatt = device.connectGatt$3(
  context,
  false,
  BluetoothGattCallback.implement(
    onConnectionStateChange: (gatt, status, newState) {/* connected */},
    onServicesDiscovered: (gatt, status) {/* find the echo */},
    onCharacteristicWrite: (gatt, characteristic, status) {/* read it */},
    onCharacteristicRead: (gatt, characteristic, value, status) {},
  ),
  BluetoothDevice.TRANSPORT_LE,
  BluetoothDevice.PHY_LE_1M_MASK,
)!;
gatt.discoverServices();
gatt.writeCharacteristic(echo, JByteArray.of(bytes),
    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);
gatt.readCharacteristic(echo);
gatt.disconnect();
gatt.close(); // after the disconnection is reported
''',
  ios: r'''
// openGattServer and addService
final manager = CBPeripheralManager.alloc().initWithDelegate(
  CBPeripheralManagerDelegate.implement(
    peripheralManagerDidUpdateState_: (manager) {/* poweredOn */},
    peripheralManager_didAddService_error_: (manager, service, error) {},
    peripheralManagerDidStartAdvertising_error_: (manager, error) {},
    peripheralManager_didReceiveReadRequest_: (manager, request) {
      request.value = value.toNSData();
      manager.respondToRequest(request,
          withResult: CBATTError.CBATTErrorSuccess);
    },
    peripheralManager_didReceiveWriteRequests_: (manager, requests) {},
    peripheralManager_central_didSubscribeToCharacteristic_:
        (manager, central, characteristic) {/* a subscriber */},
    peripheralManagerIsReadyToUpdateSubscribers_: (manager) {
      /* retry the updateValue that returned false */
    },
  ),
  queue: null,
);
final characteristic = CBMutableCharacteristic.alloc().initWithType(
  CBUUID.UUIDWithString(stream.toNSString()),
  properties: CBCharacteristicProperties.CBCharacteristicPropertyNotify,
  value: null,
  permissions: 0,
);
manager.addService(
  CBMutableService.alloc().initWithType(
    CBUUID.UUIDWithString(lab.toNSString()),
    primary: true,
  )..characteristics$1 = NSArray.of([characteristic]),
);

// startAdvertising
manager.startAdvertising({
  CBAdvertisementDataLocalNameKey: 'bt_kit Lab',
  CBAdvertisementDataServiceUUIDsKey: [CBUUID.UUIDWithString(lab.toNSString())],
}.toNSDictionary());

// notify: false while the transmit queue is full
manager.updateValue(packet.toNSData(),
    forCharacteristic: characteristic, onSubscribedCentrals: null);

// Phone B: one connection cycle.
central.connectPeripheral(peripheral, options: null);
peripheral.delegate = CBPeripheralDelegate.implement(
  peripheral_didDiscoverServices_: (peripheral, error) {/* then chars */},
  peripheral_didWriteValueForCharacteristic_error_:
      (peripheral, characteristic, error) {/* read it */},
  peripheral_didUpdateValueForCharacteristic_error_:
      (peripheral, characteristic, error) {/* characteristic.value */},
);
peripheral.discoverServices(null);
peripheral.writeValue(bytes.toNSData(),
    forCharacteristic: echo,
    type: CBCharacteristicWriteType.CBCharacteristicWriteWithResponse);
peripheral.readValueForCharacteristic(echo);
central.cancelPeripheralConnection(peripheral);
''',
);
