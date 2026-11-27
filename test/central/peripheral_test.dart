import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final heartRateUuid = BluetoothUuid.short(0x180d);
final measurementUuid = BluetoothUuid.short(0x2a37);
final controlUuid = BluetoothUuid.short(0x2a39);
final batteryUuid = BluetoothUuid.short(0x180f);
final levelUuid = BluetoothUuid.short(0x2a19);

final class Profile {
  final slowGate = Completer<void>();
  late final slow = LocalCharacteristic(
    BluetoothUuid.short(0x2a3a),
    properties: const CharacteristicProperties.of(read: true),
    onRead: (_) async {
      await slowGate.future;
      return [0x01];
    },
  );
  final measurement = LocalCharacteristic(
    measurementUuid,
    properties: const CharacteristicProperties.of(notify: true, indicate: true),
    descriptors: [LocalDescriptor.userDescription('Heart rate')],
  );
  final control = LocalCharacteristic(
    controlUuid,
    properties: const CharacteristicProperties.of(read: true, write: true),
    value: [0x00],
  );
  final level = LocalCharacteristic(
    levelUuid,
    properties: const CharacteristicProperties.of(read: true, notify: true),
    value: [0x64],
  );

  late final heartRate = LocalService(heartRateUuid, [
    measurement,
    control,
    slow,
  ]);
  late final battery = LocalService(batteryUuid, [level]);
}

void main() {
  late FakeBluetooth bluetooth;
  late Profile profile;
  late FakePeripheral sensor;
  late BtKit bt;

  setUp(() {
    bluetooth = FakeBluetooth.install();
    bt = BtKit.instance;
    profile = Profile();
    sensor = FakePeripheral(
      id: 'C4:7C:8D:6A:12:34',
      advertisement: AdvertisementData(
        localName: 'Sensor',
        serviceUuids: [heartRateUuid],
      ),
      services: [profile.heartRate],
    );
    bluetooth.add(sensor);
  });

  tearDown(FakeBluetooth.uninstall);

  Future<Peripheral> connected() async {
    final peripheral = (await bt.peripheral(sensor.id))!;
    await peripheral.connect();
    await peripheral.discoverServices();
    return peripheral;
  }

  GattCharacteristic characteristic(Peripheral p, BluetoothUuid uuid) =>
      p.characteristic(heartRateUuid, uuid) ??
      p.characteristic(batteryUuid, uuid)!;

  group('scanning', () {
    test('finds peripherals that match a filter', () async {
      bluetooth.add(
        FakePeripheral(
          id: 'AA:BB:CC:DD:EE:FF',
          advertisement: const AdvertisementData(localName: 'Lamp'),
        ),
      );
      final ad = await bt
          .scan(const ScanOptions(filters: [AdvertisementFilter(name: 'Lamp')]))
          .first;
      expect(ad.peripheral.id, 'AA:BB:CC:DD:EE:FF');
      expect(() => ad.native, throwsUnsupportedError);
    });

    test('reports the scan state', () async {
      final subscription = bt.scan().listen((_) {});
      await pumpEventQueue();
      expect(bt.isScanning, isTrue);
      expect(bt.currentScan, const ScanOptions());
      await subscription.cancel();
      await pumpEventQueue();
      expect(bt.isScanning, isFalse);
    });

    test('fails without permission', () async {
      bluetooth.permissions[BluetoothPermission.scan] = PermissionStatus.denied;
      await expectLater(
        bt.scan().first,
        throwsA(isA<BluetoothPermissionException>()),
      );
      bluetooth.requestAnswer = PermissionStatus.permanentlyDenied;
      final statuses = await bt.requestPermissions();
      expect(
        statuses[BluetoothPermission.scan],
        PermissionStatus.permanentlyDenied,
      );
    });

    test('fails while Bluetooth is off', () async {
      bluetooth.adapterState = AdapterState.poweredOff;
      await expectLater(
        bt.scan().first,
        throwsA(isA<BluetoothUnavailableException>()),
      );
    });
  });

  group('values', () {
    test('reads and writes update lastValue and valueChanges', () async {
      final peripheral = await connected();
      final control = characteristic(peripheral, controlUuid);
      final changes = <List<int>>[];
      control.valueChanges.listen(changes.add);
      expect(control.lastValue, isNull);

      expect(await control.read(), [0x00]);
      await control.write([0x01]);
      await pumpEventQueue();

      expect(control.lastValue, [0x01]);
      expect(changes, [
        [0x00],
        [0x01],
      ]);
      expect(sensor.value(profile.control), [0x01]);
    });

    test('a write without response is applied when it completes', () async {
      final peripheral = await connected();
      await characteristic(
        peripheral,
        controlUuid,
      ).write([0x07], withResponse: false);
      expect(sensor.value(profile.control), [0x07]);
    });

    test('descriptors keep their last value', () async {
      final peripheral = await connected();
      final description = characteristic(
        peripheral,
        measurementUuid,
      ).descriptors.firstWhere((d) => d.uuid != BluetoothUuid.short(0x2902));
      expect(String.fromCharCodes(await description.read()), 'Heart rate');
      expect(description.lastValue, isNotNull);
    });

    test('rediscovery starts with empty values', () async {
      final peripheral = await connected();
      await characteristic(peripheral, controlUuid).read();
      await peripheral.discoverServices();
      expect(characteristic(peripheral, controlUuid).lastValue, isNull);
    });
  });

  group('subscriptions', () {
    test('deliver pushes and update the last value', () async {
      final peripheral = await connected();
      final measurement = characteristic(peripheral, measurementUuid);
      final values = <List<int>>[];
      final subscription = measurement.subscribe().listen(values.add);
      await pumpEventQueue();
      expect(measurement.isNotifying, isTrue);
      expect(sensor.subscription(profile.measurement), NotifyMode.notification);

      await sensor.notify(profile.measurement, [0x00, 72]);
      await pumpEventQueue();
      expect(values, [
        [0x00, 72],
      ]);
      expect(measurement.lastValue, [0x00, 72]);

      await subscription.cancel();
      await pumpEventQueue();
      expect(measurement.isNotifying, isFalse);
      expect(sensor.subscription(profile.measurement), isNull);
    });

    test('use the mode asked for and refuse a second mode', () async {
      final peripheral = await connected();
      final measurement = characteristic(peripheral, measurementUuid);
      final subscription = measurement
          .subscribe(mode: NotifyMode.indication)
          .listen((_) {});
      await pumpEventQueue();
      expect(sensor.subscription(profile.measurement), NotifyMode.indication);
      expect(
        () => measurement.subscribe(mode: NotifyMode.notification),
        throwsStateError,
      );
      expect(
        measurement.subscribe(mode: NotifyMode.indication),
        isA<Stream<Uint8List>>(),
      );
      await subscription.cancel();
      await pumpEventQueue();
      measurement.subscribe(mode: NotifyMode.notification).listen((_) {});
      await pumpEventQueue();
      expect(sensor.subscription(profile.measurement), NotifyMode.notification);
    });

    test('fail for a mode the characteristic lacks', () async {
      final peripheral = await connected();
      await expectLater(
        characteristic(
          peripheral,
          controlUuid,
        ).subscribe(mode: NotifyMode.indication),
        emitsError(isA<UnsupportedFeatureException>()),
      );
    });

    test('cannot choose the mode where the platform decides', () async {
      bluetooth.capabilities = FakeBluetooth.iosCapabilities;
      final peripheral = await connected();
      await expectLater(
        characteristic(
          peripheral,
          measurementUuid,
        ).subscribe(mode: NotifyMode.indication),
        emitsError(isA<UnsupportedFeatureException>()),
      );
    });

    test('end with DisconnectedException and its reason', () async {
      final peripheral = await connected();
      final done = expectLater(
        characteristic(peripheral, measurementUuid).subscribe(),
        emitsError(
          isA<DisconnectedException>().having(
            (e) => e.reason?.cause,
            'cause',
            DisconnectCause.remote,
          ),
        ),
      );
      await pumpEventQueue();
      sensor.disconnect();
      await done;
    });
  });

  group('services changed', () {
    test('invalidates services until they are discovered again', () async {
      final peripheral = await connected();
      final control = characteristic(peripheral, controlUuid);
      final measurement = characteristic(peripheral, measurementUuid);
      final changed = peripheral.servicesChanged.first;
      final ended = expectLater(
        measurement.subscribe(),
        emitsError(isA<AttributeInvalidatedException>()),
      );
      await pumpEventQueue();

      await sensor.addService(profile.battery);
      await changed;
      await ended;
      expect(peripheral.services, isEmpty);
      expect(control.service.isInvalidated, isTrue);
      await expectLater(
        control.read(),
        throwsA(isA<AttributeInvalidatedException>()),
      );

      await peripheral.discoverServices();
      expect(peripheral.services.map((s) => s.uuid), [
        heartRateUuid,
        batteryUuid,
      ]);
      expect(await characteristic(peripheral, levelUuid).read(), [0x64]);
    });

    test('fails operations queued before the change', () async {
      final peripheral = await connected();
      final inFlight = characteristic(peripheral, BluetoothUuid.short(0x2a3a));
      final first = inFlight.read();
      final queued = characteristic(peripheral, controlUuid).read();
      await pumpEventQueue();
      await sensor.addService(profile.battery);
      await pumpEventQueue();
      profile.slowGate.complete();
      expect(await first, [0x01]);
      await expectLater(queued, throwsA(isA<AttributeInvalidatedException>()));
    });
  });

  group('link', () {
    test('MTU changes are reported', () async {
      final peripheral = await connected();
      expect(peripheral.mtu, 23);
      final changes = peripheral.mtuChanges.first;
      final event = bt.events.firstWhere((e) => e is MtuChanged);
      expect(await peripheral.requestMtu(517), 247);
      expect(await changes, 247);
      expect((await event as MtuChanged).mtu, 247);
      expect(peripheral.maximumWriteLength(withResponse: false), 244);
    });

    test('connection priority is Android only', () async {
      final peripheral = await connected();
      await peripheral.requestConnectionPriority(ConnectionPriority.high);
      expect(sensor.connectionPriority, ConnectionPriority.high);

      bluetooth.capabilities = FakeBluetooth.iosCapabilities;
      await expectLater(
        peripheral.requestConnectionPriority(ConnectionPriority.high),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    });

    test('PHY requests are checked against the capabilities', () async {
      final peripheral = await connected();
      final changes = peripheral.phyChanges.first;
      final phy = await peripheral.setPreferredPhy(
        tx: {Phy.le2M},
        rx: {Phy.le1M, Phy.le2M},
      );
      expect(phy, const PhyInfo(tx: Phy.le2M, rx: Phy.le2M));
      expect(await changes, phy);
      expect(await peripheral.readPhy(), phy);

      bluetooth.capabilities = FakeBluetooth.iosCapabilities;
      await expectLater(
        peripheral.readPhy(),
        throwsA(isA<UnsupportedFeatureException>()),
      );
      await expectLater(
        peripheral.setPreferredPhy(tx: {}, rx: {Phy.le1M}),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    });
  });

  group('disconnections', () {
    for (final (name, drop, cause) in [
      ('the app', (Peripheral p) => p.disconnect(), DisconnectCause.requested),
      ('the peripheral', (_) => sensor.disconnect(), DisconnectCause.remote),
      ('range', (_) => sensor.inRange = false, DisconnectCause.linkLoss),
      (
        'Bluetooth',
        (_) => bluetooth.adapterState = AdapterState.poweredOff,
        DisconnectCause.adapterOff,
      ),
    ]) {
      test('caused by $name are reported as ${cause.name}', () async {
        final peripheral = await connected();
        final event = bt.events.firstWhere(
          (e) =>
              e is ConnectionChanged &&
              e.state == BluetoothConnectionState.disconnected,
        );
        drop(peripheral);
        final change = await event as ConnectionChanged;
        expect(change.reason?.cause, cause);
        expect(peripheral.lastDisconnect?.cause, cause);
      });
    }

    test('pending operations fail with the reason', () async {
      final peripheral = await connected();
      bluetooth.timeoutNext();
      final pending = peripheral.readRssi();
      await pumpEventQueue();
      sensor.disconnect();
      await expectLater(
        pending,
        throwsA(
          isA<DisconnectedException>().having(
            (e) => e.reason?.cause,
            'cause',
            DisconnectCause.remote,
          ),
        ),
      );
    });

    test('a connection that never completes times out', () async {
      sensor.connectable = false;
      final peripheral = (await bt.peripheral(sensor.id))!;
      await expectLater(
        peripheral.connect(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<OperationTimeoutException>()),
      );
      expect(peripheral.connectionState, BluetoothConnectionState.disconnected);
      expect(peripheral.lastDisconnect?.cause, DisconnectCause.requested);
    });
  });

  group('app connections', () {
    test('list what this app is connected to', () async {
      expect(bt.connectedPeripherals, isEmpty);
      final peripheral = await connected();
      await pumpEventQueue();
      expect(bt.connectedPeripherals, [peripheral]);
      expect(await bt.systemPeripherals(), [peripheral]);
      await peripheral.disconnect();
      await pumpEventQueue();
      expect(bt.connectedPeripherals, isEmpty);
    });

    test('events report connection changes in order', () async {
      final states = <BluetoothConnectionState>[];
      bt.events.listen((event) {
        if (event case ConnectionChanged(:final state)) states.add(state);
      });
      final peripheral = await connected();
      await peripheral.disconnect();
      await pumpEventQueue();
      expect(states, [
        BluetoothConnectionState.connecting,
        BluetoothConnectionState.connected,
        BluetoothConnectionState.disconnected,
      ]);
    });

    test('name changes are reported', () async {
      final peripheral = await connected();
      final names = peripheral.nameChanges.first;
      sensor.name = 'Renamed';
      expect(await names, 'Renamed');
    });
  });

  group('scripted failures', () {
    test('failNext answers the next request with an ATT error', () async {
      final peripheral = await connected();
      bluetooth.failNext(GattError.insufficientAuthentication);
      await expectLater(
        characteristic(peripheral, controlUuid).read(),
        throwsA(
          isA<GattException>().having(
            (e) => e.error,
            'error',
            GattError.insufficientAuthentication,
          ),
        ),
      );
      expect(await characteristic(peripheral, controlUuid).read(), [0x00]);
    });

    test('timeoutNext keeps the queue busy until the link drops', () async {
      final peripheral = await connected();
      bluetooth.timeoutNext();
      await expectLater(
        peripheral.readRssi(timeout: const Duration(milliseconds: 10)),
        throwsA(isA<OperationTimeoutException>()),
      );
      var answered = false;
      final next = peripheral.readRssi().then((_) => answered = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(answered, isFalse);
      sensor.disconnect();
      await expectLater(next, throwsA(isA<DisconnectedException>()));
    });
  });
}
