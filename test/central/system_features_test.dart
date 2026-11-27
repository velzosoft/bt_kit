import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/platform/background_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/capabilities.dart';
import '../fakes/test_central.dart';

void main() {
  late TestCentral central;
  late BtKit bt;
  final heartRate = BluetoothUuid.short(0x180d);

  setUp(() {
    central = TestCentral();
    bt = BtKit.instance;
  });

  tearDown(TestCentral.uninstall);

  group('background delivery', () {
    test(
      'scan results arrive as advertisements of known peripherals',
      () async {
        final sensor = central.add('AA:BB:CC:DD:EE:FF');
        final peripheral = await bt.peripheral(sensor.id);
        final events = <BackgroundEvent>[];
        bt.backgroundEvents.listen(events.add);

        central.background.signalController.add(ScanSignal([hitFor(sensor)]));
        await pumpEventQueue();

        final result = events.single as BackgroundScanResult;
        expect(result.advertisements.single.peripheral, same(peripheral));
        expect(result.errorCode, isNull);
      },
    );

    test('presence arrives with the companion id', () async {
      final events = <BackgroundEvent>[];
      bt.backgroundEvents.listen(events.add);

      central.background.signalController.add(
        const PresenceSignal(4, CompanionPresence.appeared),
      );
      await pumpEventQueue();

      final presence = events.single as CompanionPresenceChanged;
      expect(presence.companionId, '4');
      expect(presence.presence, CompanionPresence.appeared);
    });

    test('a background scan needs filters Android checks itself', () async {
      expect(
        () => bt.startBackgroundScan(const ScanOptions()),
        throwsArgumentError,
      );
      expect(
        () => bt.startBackgroundScan(
          const ScanOptions(
            filters: [AdvertisementFilter(nameContains: 'Polar')],
          ),
        ),
        throwsArgumentError,
      );

      final options = ScanOptions(services: [heartRate]);
      await bt.startBackgroundScan(options);
      await bt.stopBackgroundScan();

      expect(central.background.scans.single, options);
      expect(central.background.stopped, 1);
    });

    test('a background scan needs the scan permission', () async {
      central.denied.add(BluetoothPermission.scan);

      await expectLater(
        bt.startBackgroundScan(ScanOptions(services: [heartRate])),
        throwsA(isA<BluetoothPermissionException>()),
      );
    });

    test('iOS has no background delivery', () {
      central.capabilities = capabilities(backgroundEvents: false);

      expect(
        () => bt.startBackgroundScan(ScanOptions(services: [heartRate])),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    });
  });

  group('state restoration', () {
    test('replays the restored peripherals to each listener', () async {
      final watch = central.add('5F1C2A0B-0000-4000-8000-000000000001')
        ..connectionState = BluetoothConnectionState.connected;
      central.restore([watch], [heartRate]);

      final first = await bt.restored.first as RestoredCentral;
      final second = await bt.restored.first as RestoredCentral;

      expect(first.peripherals.single.id, watch.id);
      expect(first.peripherals.single, same(second.peripherals.single));
      expect(first.scanServices, [heartRate]);
      expect(bt.connectedPeripherals.single.id, watch.id);
    });

    test('reports the restored peripheral role', () async {
      final restored = bt.restored.first;
      await pumpEventQueue();

      central.peripheralRole.restore([heartRate], advertising: true);

      final role = await restored as RestoredPeripheralRole;
      expect(role.services, [heartRate]);
      expect(role.advertising, isTrue);
    });
  });

  test('configure must come before the first use', () {
    expect(
      () => BtKit.configure(const BtKitOptions(restoreIdentifier: 'app')),
      throwsStateError,
    );
  });

  group('system connections', () {
    test('passes on connections of any app', () async {
      final events = <SystemConnectionEvent>[];
      bt.systemConnections(services: [heartRate]).listen(events.add);
      await pumpEventQueue();

      final event = SystemConnectionEvent(
        deviceId: 'AA:BB:CC:DD:EE:FF',
        connected: true,
        transport: LinkTransport.classic,
        at: DateTime(2026),
      );
      central.connectionEvents.add(event);
      await pumpEventQueue();

      expect(events, [event]);
    });

    test('need the connect permission', () async {
      central.denied.add(BluetoothPermission.connect);

      await expectLater(
        bt.systemConnections(),
        emitsError(isA<BluetoothPermissionException>()),
      );
    });
  });

  group('audio profiles', () {
    const headphones = AudioConnection(
      deviceId: '00:11:22:33:44:55',
      profile: AudioProfile.a2dp,
      state: BluetoothConnectionState.connected,
      isPlaying: true,
    );

    test('lists connections per profile', () async {
      central.audio.connected.add(headphones);

      expect(await bt.audio.connections(), [headphones]);
      expect(await bt.audio.connections({AudioProfile.leAudio}), isEmpty);
    });

    test('reports changes', () async {
      final changes = <AudioConnection>[];
      bt.audio.changes.listen(changes.add);
      await pumpEventQueue();

      central.audio.changeController.add(headphones);
      await pumpEventQueue();

      expect(changes, [headphones]);
    });

    test('iOS keeps audio state to itself', () async {
      central.capabilities = capabilities(audioProfiles: false);

      await expectLater(
        bt.audio.connections(),
        throwsA(isA<UnsupportedFeatureException>()),
      );
      await expectLater(
        bt.audio.changes,
        emitsError(isA<UnsupportedFeatureException>()),
      );
    });
  });

  group('location permission', () {
    setUp(() {
      central.scanNeeds = {
        BluetoothPermission.scan,
        BluetoothPermission.location,
      };
    });

    test('scans need it where the manifest does not disavow it', () async {
      central.denied.add(BluetoothPermission.location);

      await expectLater(
        bt.scan().first,
        throwsA(
          isA<BluetoothPermissionException>().having(
            (e) => e.statuses.keys,
            'missing',
            [BluetoothPermission.location],
          ),
        ),
      );
      await expectLater(
        bt.startBackgroundScan(ScanOptions(services: [heartRate])),
        throwsA(isA<BluetoothPermissionException>()),
      );
    });

    test('the default permissions include it then', () async {
      expect((await bt.checkPermissions()).keys, {
        BluetoothPermission.scan,
        BluetoothPermission.connect,
        BluetoothPermission.location,
      });
      central.scanNeeds = {BluetoothPermission.scan};
      expect((await bt.checkPermissions()).keys, BtKit.centralPermissions);
    });
  });
}
