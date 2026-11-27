import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/capabilities.dart';
import '../fakes/test_central.dart';

void main() {
  late TestCentral central;
  late TestPeripheral tag;
  late Peripheral peripheral;

  setUp(() async {
    central = TestCentral();
    tag = central.add('AA:BB:CC:DD:EE:FF');
    peripheral = (await BtKit.instance.peripheral(tag.id))!;
  });

  tearDown(TestCentral.uninstall);

  DistanceMeasurement at(double meters) => DistanceMeasurement(
    meters: meters,
    method: DistanceMethod.channelSounding,
    timestamp: DateTime(2026),
  );

  test('measurements stream until cancelled', () async {
    final samples = <DistanceMeasurement>[];
    final subscription = peripheral
        .measureDistance(rate: MeasurementRate.high)
        .listen(samples.add);
    await pumpEventQueue();

    tag.measuring!
      ..add(at(1.5))
      ..add(at(1.2));
    await pumpEventQueue();
    await subscription.cancel();

    expect(samples.map((s) => s.meters), [1.5, 1.2]);
    expect(tag.distances.single, (
      DistanceMethod.channelSounding,
      MeasurementRate.high,
    ));
    expect(tag.measuring!.hasListener, isFalse);
  });

  test('one measurement runs per peripheral', () async {
    final first = peripheral.measureDistance().listen((_) {});
    await pumpEventQueue();

    await expectLater(
      peripheral.measureDistance(),
      emitsError(isA<RangingException>()),
    );

    await first.cancel();
    final second = peripheral.measureDistance().listen((_) {});
    await pumpEventQueue();
    expect(tag.distances, hasLength(2));
    await second.cancel();
  });

  test('platform errors reach the listener', () async {
    final errors = <Object>[];
    peripheral.measureDistance().listen((_) {}, onError: errors.add);
    await pumpEventQueue();

    tag.measuring!.addError(const RangingException('peer not found'));
    await pumpEventQueue();

    expect(errors.single, isA<RangingException>());
  });

  test('each method needs its capability', () async {
    central.capabilities = capabilities(
      channelSounding: false,
      rssiRanging: false,
    );

    await expectLater(
      peripheral.measureDistance(),
      emitsError(
        isA<UnsupportedFeatureException>().having(
          (e) => e.feature,
          'feature',
          'channelSounding',
        ),
      ),
    );
    await expectLater(
      peripheral.measureDistance(method: DistanceMethod.rssi),
      emitsError(
        isA<UnsupportedFeatureException>().having(
          (e) => e.feature,
          'feature',
          'rssiRanging',
        ),
      ),
    );
  });

  test('measuring needs the ranging permission', () async {
    central.denied.add(BluetoothPermission.ranging);

    await expectLater(
      peripheral.measureDistance(),
      emitsError(isA<BluetoothPermissionException>()),
    );
    expect(tag.distances, isEmpty);
  });
}
