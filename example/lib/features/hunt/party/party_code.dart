import '../../../widgets/code_sheet.dart';

const partyCode = CodeSample(
  title: 'Party: a GATT server and its seekers',
  layer2: r'''
// The hider's phone serves the game.
final state = LocalCharacteristic(
  partyState,
  properties: const CharacteristicProperties.of(read: true, notify: true),
  onRead: (_) => [phase, round],
);
final game = LocalCharacteristic(
  partyGame,
  properties: const CharacteristicProperties.of(read: true),
  onRead: (_) => utf8.encode(jsonEncode(currentGame)), // long reads too
);
final finish = LocalCharacteristic(
  partyFinish,
  properties: const CharacteristicProperties.of(write: true),
  onWrite: (request) => recordWinner(request.value),
);

await bt.requestPermissions(BtKit.peripheralPermissions);
final server = await bt.openGattServer(
  services: [LocalService(party, [game, state, finish])],
);
await bt.startAdvertising(AdvertiseOptions(serviceUuids: [party]));

// Go: every subscribed seeker hears it at once.
await server.notify(state, [go, round]);
print('${server.subscribers(state).length} seekers');

// A seeker's phone joins.
final host = partyAdvertisement.peripheral;
await host.connect();
await host.discoverServices();
final rules = await host.characteristic(party, partyGame)!.read();

host.characteristic(party, partyState)!.subscribe().listen((value) {
  if (value[0] == go) startCountdown();
});

// Found it: the hider's phone gets the time.
await host
    .characteristic(party, partyFinish)!
    .write(utf8.encode(jsonEncode({'player': 'Sam', 'ms': 12345})));
''',
  android: r'''
// Hider
final callback = BluetoothGattServerCallback.implement(
  onCharacteristicReadRequest: (device, requestId, offset, characteristic) {
    final value = JByteArray.of(valueFor(characteristic!).sublist(offset));
    server.sendResponse(
      device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value,
    );
  },
  onCharacteristicWriteRequest: (device, requestId, characteristic,
      prepared, responseNeeded, offset, value) {
    recordWinner(value!);
    if (responseNeeded) {
      server.sendResponse(
        device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null,
      );
    }
  },
  onNotificationSent: (device, status) => sendNextNotification(),
);
final server = manager.openGattServer(context, callback)!;

final state = BluetoothGattCharacteristic(
  UUID.fromString(partyState.toJString()),
  BluetoothGattCharacteristic.PROPERTY_READ |
      BluetoothGattCharacteristic.PROPERTY_NOTIFY,
  BluetoothGattCharacteristic.PERMISSION_READ,
)..addDescriptor(
    BluetoothGattDescriptor(
      UUID.fromString(clientConfiguration.toJString()),
      BluetoothGattDescriptor.PERMISSION_READ |
          BluetoothGattDescriptor.PERMISSION_WRITE,
    ),
  );
final service = BluetoothGattService(
  UUID.fromString(party.toJString()),
  BluetoothGattService.SERVICE_TYPE_PRIMARY,
)..addCharacteristic(state);
server.addService(service); // then wait for onServiceAdded

// Go: to each subscribed seeker, one at a time.
server.notifyCharacteristicChanged(
  seeker, state, false, JByteArray.of([go, round]),
);

// Seeker
final gatt = device.connectGatt$3(
  context, false, gattCallback,
  BluetoothDevice.TRANSPORT_LE, BluetoothDevice.PHY_LE_1M_MASK,
)!;
gatt.discoverServices(); // then onServicesDiscovered
final stateOnHost = gatt
    .getService(UUID.fromString(party.toJString()))!
    .getCharacteristic(UUID.fromString(partyState.toJString()))!;
gatt.setCharacteristicNotification(stateOnHost, true);
gatt.writeDescriptor(
  stateOnHost.getDescriptor(UUID.fromString(clientConfiguration.toJString()))!,
  BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE!,
);
gatt.writeCharacteristic(
  finishOnHost,
  JByteArray.of(finishJson),
  BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
);
''',
  ios: r'''
// Hider
final state = CBMutableCharacteristic.alloc().initWithType(
  CBUUID.UUIDWithString(partyState.toNSString()),
  properties: CBCharacteristicProperties.CBCharacteristicPropertyRead |
      CBCharacteristicProperties.CBCharacteristicPropertyNotify,
  value: null,
  permissions: CBAttributePermissions.CBAttributePermissionsReadable,
);
final service = CBMutableService.alloc().initWithType(
  CBUUID.UUIDWithString(party.toNSString()),
  primary: true,
)..characteristics$1 = NSArray.of([game, state, finish]);

final delegate = CBPeripheralManagerDelegate.implement(
  peripheralManagerDidUpdateState_: (manager) {
    if (manager.state != CBManagerState.CBManagerStatePoweredOn) return;
    manager.addService(service); // then didAddService
  },
  peripheralManager_didReceiveReadRequest_: (manager, request) {
    request.value = valueFor(request.characteristic)
        .sublist(request.offset)
        .toNSData();
    manager.respondToRequest(
      request, withResult: CBATTError.CBATTErrorSuccess,
    );
  },
  peripheralManager_didReceiveWriteRequests_: (manager, requests) {
    final first = CBATTRequest.as(requests.objectAtIndex(0));
    recordWinner(first.value!.toList());
    manager.respondToRequest(
      first, withResult: CBATTError.CBATTErrorSuccess,
    );
  },
  // false from updateValue means "full"; send again here.
  peripheralManagerIsReadyToUpdateSubscribers_: (manager) =>
      sendPendingUpdates(),
);
final manager = CBPeripheralManager.alloc().initWithDelegate(delegate);

// Go: to every subscribed central.
manager.updateValue(
  [go, round].toNSData(),
  forCharacteristic: state,
  onSubscribedCentrals: null,
);

// Seeker
central.connectPeripheral(host, options: null);
host.discoverServices(null); // then discoverCharacteristics
host.setNotifyValue(true, forCharacteristic: stateOnHost);
host.writeValue(
  finishJson.toNSData(),
  forCharacteristic: finishOnHost,
  type: CBCharacteristicWriteType.CBCharacteristicWriteWithResponse,
);
''',
);
