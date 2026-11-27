import '../../widgets/code_sheet.dart';

const fileBeamCode = CodeSample(
  title: 'File beam: GATT server and L2CAP',
  layer2: r'''
final bt = BtKit.instance;
final fileBeam = BluetoothUuid.parse('f3b1a020-6b2c-4e7a-9a54-7c2d8e0b1a00');
final psmUuid = BluetoothUuid.parse('f3b1a021-6b2c-4e7a-9a54-7c2d8e0b1a00');

// Receiver: publish an L2CAP channel, serve its PSM, advertise.
await bt.requestPermissions(BtKit.peripheralPermissions);
// secure: true (the default) makes the phones pair first.
final l2cap = await bt.publishL2capChannel(secure: false);
final server = await bt.openGattServer(services: [
  LocalService(fileBeam, [
    LocalCharacteristic(
      psmUuid,
      properties: const CharacteristicProperties.of(read: true),
      value: [l2cap.psm & 0xff, l2cap.psm >> 8], // uint16, little-endian
    ),
  ]),
]);
final advertising = await bt.startAdvertising(
  AdvertiseOptions(serviceUuids: [fileBeam]),
);
l2cap.channels.listen((channel) {
  // Chunks split anywhere: parse 'BEAM', name, length, payload, CRC-32.
  channel.input.listen(parser.add, onDone: parser.close);
});

// Sender: a device in the shared scan whose advertisement lists fileBeam.
final receiver = ad.peripheral;
await receiver.connect();
await receiver.discoverServices();
final value = await receiver.characteristic(fileBeam, psmUuid)!.read();
final channel = await receiver.openL2capChannel(
  value[0] | value[1] << 8,
  secure: false,
);
await channel.write(header);
for (var i = 0; i < bytes.length; i += 8192) {
  await channel.write(bytes.sublist(i, min(i + 8192, bytes.length)));
}
await channel.write(crc32);
final answer = await channel.input.first; // 0x06: checksum OK
await channel.close();
await receiver.disconnect();

// Receiver, when leaving the screen:
await advertising.stop();
await server.close();
await l2cap.close();
''',
  android: r'''
final context = androidApplicationContext.as(Context.type);
final manager = context
    .getSystemService$1(Context.BLUETOOTH_SERVICE!)!
    .as(BluetoothManager.type);
final adapter = manager.adapter!;
final fileBeam = 'f3b1a020-6b2c-4e7a-9a54-7c2d8e0b1a00'.toJString();
final psmUuid = 'f3b1a021-6b2c-4e7a-9a54-7c2d8e0b1a00'.toJString();

// Receiver: a server socket with a dynamic PSM.
final serverSocket = adapter.listenUsingInsecureL2capChannel();
final psm = serverSocket.psm;

late final BluetoothGattServer gattServer;
final callback = BluetoothGattServerCallback.implement(
  onCharacteristicReadRequest: (device, requestId, offset, characteristic) {
    gattServer.sendResponse(
      device!,
      requestId,
      BluetoothGatt.GATT_SUCCESS,
      offset,
      JByteArray.of([psm & 0xff, psm >> 8]),
    );
  },
);
gattServer = manager.openGattServer(context, callback)!;
final service = BluetoothGattService(
  UUID.fromString(fileBeam)!,
  BluetoothGattService.SERVICE_TYPE_PRIMARY,
);
service.addCharacteristic(
  BluetoothGattCharacteristic(
    UUID.fromString(psmUuid)!,
    BluetoothGattCharacteristic.PROPERTY_READ,
    BluetoothGattCharacteristic.PERMISSION_READ,
  ),
);
gattServer.addService(service); // Then wait for onServiceAdded.

final parameters = (AdvertisingSetParameters$Builder()
      ..setLegacyMode(true)
      ..setConnectable(true)
      ..setScannable(true))
    .build()!;
final data = (AdvertiseData$Builder()
      ..addServiceUuid(ParcelUuid.fromString(fileBeam)!))
    .build()!;
adapter.bluetoothLeAdvertiser!.startAdvertisingSet(
  parameters, data, null, null, null, AdvertisingSetCallback.implement(),
);

// accept() and read() block, so bt_kit runs them on background isolates.
final socket = serverSocket.accept()!;
final buffer = JByteArray(4096);
final count = socket.inputStream!.read$1(buffer);

// Sender: connect a socket to the PSM it read over GATT.
final l2cap = device.createInsecureL2capChannel(psm);
l2cap.connect(); // Blocking, on a background isolate.
final output = l2cap.outputStream!;
output.write$1(JByteArray.of(chunk), 0, chunk.length);
output.flush();
l2cap.close();
''',
  ios: r'''
final fileBeam = CBUUID.UUIDWithString(
  'f3b1a020-6b2c-4e7a-9a54-7c2d8e0b1a00'.toNSString(),
);
final psmUuid = CBUUID.UUIDWithString(
  'f3b1a021-6b2c-4e7a-9a54-7c2d8e0b1a00'.toNSString(),
);
var psm = 0;

// Receiver: one CBPeripheralManager publishes, serves and advertises.
final delegate = CBPeripheralManagerDelegate.implement(
  peripheralManagerDidUpdateState_: (manager) {
    if (manager.state != CBManagerState.CBManagerStatePoweredOn) return;
    manager.publishL2CAPChannelWithEncryption(false);
  },
  peripheralManager_didPublishL2CAPChannel_error_: (manager, published, _) {
    psm = published;
    final characteristic = CBMutableCharacteristic.alloc().initWithType(
      psmUuid,
      properties: CBCharacteristicProperties.CBCharacteristicPropertyRead,
      value: null, // Answered in didReceiveReadRequest.
      permissions: CBAttributePermissions.CBAttributePermissionsReadable,
    );
    final service = CBMutableService.alloc()
        .initWithType(fileBeam, primary: true)
      ..characteristics$1 = NSArray.of([characteristic]);
    manager.addService(service);
    manager.startAdvertising({
      CBAdvertisementDataLocalNameKey: 'Beam',
      CBAdvertisementDataServiceUUIDsKey: [fileBeam],
    }.toNSDictionary());
  },
  peripheralManager_didReceiveReadRequest_: (manager, request) {
    request.value = [psm & 0xff, psm >> 8].toNSData();
    manager.respondToRequest(
      request,
      withResult: CBATTError.CBATTErrorSuccess,
    );
  },
  peripheralManager_didOpenL2CAPChannel_error_: (manager, channel, _) {
    // Read on NSStreamEventHasBytesAvailable.
    channel!.inputStream
      ..delegate = streamDelegate
      ..scheduleInRunLoop(
        NSRunLoop.getMainRunLoop(),
        forMode: NSRunLoopCommonModes,
      )
      ..open();
  },
);
final manager = CBPeripheralManager.alloc().initWithDelegate$1(delegate);

// Sender: on a connected CBPeripheral.
peripheral.openL2CAPChannel(psm);
// CBPeripheralDelegate.peripheral_didOpenL2CAPChannel_error_ delivers
// the CBL2CAPChannel. Write on NSStreamEventHasSpaceAvailable:
final output = channel.outputStream
  ..delegate = streamDelegate
  ..scheduleInRunLoop(
    NSRunLoop.getMainRunLoop(),
    forMode: NSRunLoopCommonModes,
  )
  ..open();
final written = output.write(buffer, maxLength: count);
''',
);
