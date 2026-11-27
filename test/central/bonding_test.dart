import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeBluetooth bluetooth;
  late FakePeripheral lock;
  late Peripheral peripheral;

  setUp(() async {
    bluetooth = FakeBluetooth.install();
    lock = FakePeripheral(id: 'C4:7C:8D:6A:12:34');
    bluetooth.add(lock);
    peripheral = (await BtKit.instance.peripheral(lock.id))!;
  });

  tearDown(FakeBluetooth.uninstall);

  test('createBond pairs and reports each step', () async {
    final states = <BondState>[];
    peripheral.bondStates.listen(states.add);

    await peripheral.createBond();

    expect(peripheral.bondState, BondState.bonded);
    expect(states, [BondState.bonding, BondState.bonded]);
  });

  test('a bond change while connected reaches BtKit.events', () async {
    await peripheral.connect();
    final events = <PeripheralEvent>[];
    BtKit.instance.events.listen(events.add);

    lock.bondState = BondState.bonded;
    await pumpEventQueue();

    expect(events.whereType<BondChanged>().map((e) => e.state), [
      BondState.bonded,
    ]);
  });

  test('createBond on a bonded peripheral returns at once', () async {
    lock.bondState = BondState.bonded;
    final states = <BondState>[];
    peripheral.bondStates.listen(states.add);

    await peripheral.createBond();

    expect(states, isEmpty);
  });

  test('rejected pairing fails with BondException', () async {
    lock.acceptsPairing = false;

    await expectLater(peripheral.createBond(), throwsA(isA<BondException>()));
    expect(peripheral.bondState, BondState.none);
  });

  test('a timed-out pairing is cancelled', () async {
    lock.pairingTime = const Duration(milliseconds: 200);

    await expectLater(
      peripheral.createBond(timeout: const Duration(milliseconds: 20)),
      throwsA(isA<OperationTimeoutException>()),
    );
    expect(peripheral.bondState, BondState.none);
  });

  test('a cancelled pairing is cancelled on the device too', () async {
    lock.pairingTime = const Duration(milliseconds: 200);
    final token = CancelToken();

    final bonding = peripheral.createBond(cancelToken: token);
    await pumpEventQueue();
    token.cancel();

    await expectLater(bonding, throwsA(isA<OperationCancelledException>()));
    expect(peripheral.bondState, BondState.none);
  });

  test('removeBond removes it where apps can', () async {
    lock.bondState = BondState.bonded;

    expect(await peripheral.removeBond(), isTrue);
    expect(peripheral.bondState, BondState.none);
    expect(bluetooth.settingsOpened, 0);
  });

  test('removeBond opens the settings where apps cannot', () async {
    bluetooth.capabilities = withRemoveBond(false);
    lock.bondState = BondState.bonded;

    expect(await peripheral.removeBond(), isFalse);
    expect(bluetooth.settingsOpened, 1);
  });

  test('removeBond on an unbonded peripheral does nothing', () async {
    expect(await peripheral.removeBond(), isTrue);
    expect(bluetooth.settingsOpened, 0);
  });

  test('bondedPeripherals lists the bonded ones', () async {
    final other = FakePeripheral(id: 'AA:BB:CC:DD:EE:FF');
    bluetooth.add(other);
    lock.bondState = BondState.bonded;

    final bonded = await BtKit.instance.bondedPeripherals();

    expect(bonded.map((p) => p.id), [lock.id]);
    expect(bonded.single, same(peripheral));
  });

  test('bonding needs the connect permission', () async {
    bluetooth.permissions[BluetoothPermission.connect] =
        PermissionStatus.denied;

    await expectLater(
      peripheral.createBond(),
      throwsA(isA<BluetoothPermissionException>()),
    );
  });

  test('iOS has no bonding API', () async {
    bluetooth.capabilities = FakeBluetooth.iosCapabilities;

    await expectLater(
      peripheral.createBond(),
      throwsA(
        isA<UnsupportedFeatureException>().having(
          (e) => e.feature,
          'feature',
          'bonding',
        ),
      ),
    );
    await expectLater(
      BtKit.instance.bondedPeripherals(),
      throwsA(isA<UnsupportedFeatureException>()),
    );
  });
}

BluetoothCapabilities withRemoveBond(bool removeBond) {
  const c = FakeBluetooth.androidCapabilities;
  return BluetoothCapabilities(
    lowEnergy: c.lowEnergy,
    classic: c.classic,
    le2MPhy: c.le2MPhy,
    leCodedPhy: c.leCodedPhy,
    extendedAdvertising: c.extendedAdvertising,
    periodicAdvertising: c.periodicAdvertising,
    channelSounding: c.channelSounding,
    requestMtu: c.requestMtu,
    connectionPriority: c.connectionPriority,
    phy: c.phy,
    notifyMode: c.notifyMode,
    requestEnable: c.requestEnable,
    peripheralRole: c.peripheralRole,
    advertiseLocalName: c.advertiseLocalName,
    advertiseCustomData: c.advertiseCustomData,
    l2cap: c.l2cap,
    bonding: c.bonding,
    removeBond: removeBond,
    externalAccessory: c.externalAccessory,
    companionDevices: c.companionDevices,
    backgroundEvents: c.backgroundEvents,
    stateRestoration: c.stateRestoration,
    systemConnectionEvents: c.systemConnectionEvents,
    rssiRanging: c.rssiRanging,
    audioProfiles: c.audioProfiles,
    gattCacheRefresh: c.gattCacheRefresh,
    adapterName: c.adapterName,
    serverConnectionPriority: c.serverConnectionPriority,
  );
}
