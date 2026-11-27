import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scans with other Android settings are not shared', () {
    expect(const ScanOptions(), const ScanOptions());
    expect(const ScanOptions(legacyOnly: true), isNot(const ScanOptions()));
    expect(const ScanOptions(phy: ScanPhy.le1M), isNot(const ScanOptions()));
    expect(
      const ScanOptions(phy: ScanPhy.leCoded).hashCode,
      isNot(const ScanOptions().hashCode),
    );
  });

  test('describes the settings that differ from the defaults', () {
    expect(
      const ScanOptions(legacyOnly: true, phy: ScanPhy.le1M).toString(),
      'ScanOptions(mode: balanced, legacyOnly, phy: le1M)',
    );
  });

  test('legacy advertisements are never on LE Coded', () {
    expect(
      () => ScanOptions(legacyOnly: true, phy: ScanPhy.values.last),
      throwsA(isA<AssertionError>()),
    );
  });
}
