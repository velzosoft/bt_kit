import 'package:bt_radar/bluetooth/heart_rate.dart';
import 'package:flutter_test/flutter_test.dart';

const _second = Duration(seconds: 1);
const _halfSecond = Duration(milliseconds: 500);

void main() {
  group('HeartRateMeasurement.parse', () {
    test('reads a uint8 heart rate', () {
      final m = HeartRateMeasurement.parse([0x00, 72])!;
      expect(m.bpm, 72);
      expect(m.contact, SensorContact.unsupported);
      expect(m.energyExpended, isNull);
      expect(m.rrIntervals, isEmpty);
    });

    test('reads a little-endian uint16 heart rate', () {
      expect(HeartRateMeasurement.parse([0x01, 0x2c, 0x01])!.bpm, 300);
    });

    test('maps the sensor contact bits', () {
      SensorContact contact(int flags) =>
          HeartRateMeasurement.parse([flags, 72])!.contact;
      expect(contact(0x00), SensorContact.unsupported);
      expect(contact(0x02), SensorContact.unsupported);
      expect(contact(0x04), SensorContact.notDetected);
      expect(contact(0x06), SensorContact.detected);
    });

    test('reads energy expended', () {
      final m = HeartRateMeasurement.parse([0x08, 80, 0x10, 0x27])!;
      expect(m.bpm, 80);
      expect(m.energyExpended, 10000);
    });

    test('reads RR intervals in units of 1/1024 s', () {
      final m = HeartRateMeasurement.parse([0x10, 60, 0x00, 0x04, 0x00, 2])!;
      expect(m.rrIntervals, [_second, _halfSecond]);
    });

    test('reads every field at once', () {
      final m = HeartRateMeasurement.parse([
        0x1f,
        0x2c,
        0x01,
        0xe8,
        0x03,
        0x00,
        0x04,
      ])!;
      expect(m.bpm, 300);
      expect(m.contact, SensorContact.detected);
      expect(m.energyExpended, 1000);
      expect(m.rrIntervals, [_second]);
    });

    test('handles every combination of flags', () {
      for (var flags = 0; flags < 32; flags++) {
        final wide = flags & 0x01 != 0;
        final hasEnergy = flags & 0x08 != 0;
        final hasRr = flags & 0x10 != 0;
        final value = [
          flags,
          ...wide ? [0x23, 0x01] : [150],
          if (hasEnergy) ...[0x01, 0x02],
          if (hasRr) ...[0x00, 0x04, 0x00, 0x02],
        ];
        final m = HeartRateMeasurement.parse(value)!;
        final reason = 'flags 0x${flags.toRadixString(16)}';
        expect(m.bpm, wide ? 0x123 : 150, reason: reason);
        expect(m.energyExpended, hasEnergy ? 0x201 : null, reason: reason);
        expect(
          m.rrIntervals,
          hasRr ? [_second, _halfSecond] : isEmpty,
          reason: reason,
        );
        expect(m.contact, switch ((flags >> 1) & 0x03) {
          2 => SensorContact.notDetected,
          3 => SensorContact.detected,
          _ => SensorContact.unsupported,
        }, reason: reason);
      }
    });

    test('ignores reserved flag bits', () {
      final m = HeartRateMeasurement.parse([0xe0, 72])!;
      expect(m.bpm, 72);
      expect(m.energyExpended, isNull);
      expect(m.rrIntervals, isEmpty);
    });

    group('with short or malformed values', () {
      test('returns null without a heart rate', () {
        expect(HeartRateMeasurement.parse([]), isNull);
        expect(HeartRateMeasurement.parse([0x00]), isNull);
        expect(HeartRateMeasurement.parse([0x01]), isNull);
        expect(HeartRateMeasurement.parse([0x01, 0x48]), isNull);
      });

      test('leaves out truncated energy expended', () {
        final m = HeartRateMeasurement.parse([0x08, 72, 0x10])!;
        expect(m.bpm, 72);
        expect(m.energyExpended, isNull);
      });

      test('leaves out RR intervals after truncated energy', () {
        final m = HeartRateMeasurement.parse([0x18, 72, 0x10])!;
        expect(m.energyExpended, isNull);
        expect(m.rrIntervals, isEmpty);
      });

      test('drops a trailing half RR interval', () {
        final m = HeartRateMeasurement.parse([0x10, 72, 0x00, 0x04, 0x00])!;
        expect(m.rrIntervals, [_second]);
      });

      test('allows the RR flag with no intervals', () {
        expect(HeartRateMeasurement.parse([0x10, 72])!.rrIntervals, isEmpty);
      });

      test('ignores trailing bytes when no optional field is flagged', () {
        final m = HeartRateMeasurement.parse([0x00, 72, 0xff, 0xff])!;
        expect(m.bpm, 72);
        expect(m.energyExpended, isNull);
        expect(m.rrIntervals, isEmpty);
      });
    });
  });
}
