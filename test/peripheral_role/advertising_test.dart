import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/capabilities.dart';
import '../fakes/test_central.dart';

void main() {
  late TestCentral central;
  late BtKit bt;
  final service = BluetoothUuid.short(0x180d);

  setUp(() {
    central = TestCentral();
    bt = BtKit.instance;
  });

  tearDown(TestCentral.uninstall);

  AdvertiseOptions sensorData(int value) => AdvertiseOptions(
    serviceUuids: [service],
    manufacturerData: {
      0xffff: Uint8List.fromList([value]),
    },
  );

  group('update', () {
    test('replaces what is advertised', () async {
      final session = await bt.startAdvertising(sensorData(1));
      await session.update(sensorData(2));

      final advertising = central.peripheralRole.advertisements.single;
      expect(advertising.updates.single.manufacturerData[0xffff], [2]);
      expect(session.options.manufacturerData[0xffff], [2]);
    });

    test('keeps the options when the platform refuses', () async {
      final session = await bt.startAdvertising(sensorData(1));
      central.peripheralRole.advertisements.single.failNext =
          const AdvertisingException('too large');

      await expectLater(
        session.update(sensorData(2)),
        throwsA(isA<AdvertisingException>()),
      );
      expect(session.options.manufacturerData[0xffff], [1]);
      expect(session.isActive, isTrue);
    });

    test('is refused after stop', () async {
      final session = await bt.startAdvertising(sensorData(1));
      await session.stop();
      expect(() => session.update(sensorData(2)), throwsStateError);
    });

    test('checks the new options like a start', () async {
      final session = await bt.startAdvertising(sensorData(1));
      central.capabilities = capabilities(extendedAdvertising: false);
      expect(
        () => session.update(const AdvertiseOptions(extended: true)),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    });
  });

  group('periodic advertising', () {
    const periodic = AdvertiseOptions(
      extended: true,
      connectable: false,
      periodic: PeriodicAdvertising(interval: Duration(milliseconds: 500)),
    );

    test('starts with an extended, non-connectable advertisement', () async {
      final session = await bt.startAdvertising(periodic);
      expect(session.options.periodic?.interval, Duration(milliseconds: 500));
    });

    test('needs the capability', () {
      central.capabilities = capabilities(periodicAdvertising: false);
      expect(
        () => bt.startAdvertising(periodic),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    });

    test('needs an extended, non-connectable advertisement', () {
      expect(
        () => bt.startAdvertising(
          const AdvertiseOptions(
            extended: true,
            periodic: PeriodicAdvertising(),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => bt.startAdvertising(
          const AdvertiseOptions(
            connectable: false,
            periodic: PeriodicAdvertising(),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('needs an interval the controller accepts', () {
      for (final interval in [
        const Duration(milliseconds: 99),
        const Duration(seconds: 82),
      ]) {
        expect(
          () => bt.startAdvertising(
            AdvertiseOptions(
              extended: true,
              connectable: false,
              periodic: PeriodicAdvertising(interval: interval),
            ),
          ),
          throwsArgumentError,
        );
      }
    });
  });
}
