import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/hunt/party/fingerprint_hint.dart';
import 'package:bt_radar/features/hunt/party/target_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a beacon is recognized everywhere', () {
    final hint = fingerprintHint(const TargetFingerprint(beaconCode: 'K7QD'));
    expect(hint, contains('K7QD'));
    expect(hint, isNot(contains(unnamedDevicesNote)));
  });

  test('a name is enough', () {
    final hint = fingerprintHint(const TargetFingerprint(localName: 'Buds'));
    expect(hint, contains('“Buds”'));
    expect(hint, isNot(contains(unnamedDevicesNote)));
  });

  test('unnamed devices come with the Android-only note', () {
    for (final target in [
      const TargetFingerprint(address: 'AA:BB:CC:DD:EE:FF'),
      TargetFingerprint(company: 0x004c, services: [BluetoothUuid.short(1)]),
      const TargetFingerprint(),
    ]) {
      expect(fingerprintHint(target), contains(unnamedDevicesNote));
    }
  });
}
