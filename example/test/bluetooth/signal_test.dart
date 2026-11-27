import 'dart:math' as math;

import 'package:bt_radar/bluetooth/hex.dart';
import 'package:bt_radar/bluetooth/signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Signal', () {
    test('proximity has three honest bands', () {
      expect(Signal.proximity(-45), Proximity.near);
      expect(Signal.proximity(-60), Proximity.near);
      expect(Signal.proximity(-70), Proximity.around);
      expect(Signal.proximity(-80), Proximity.around);
      expect(Signal.proximity(-95), Proximity.far);
    });

    test('strength is clamped to 0..1', () {
      expect(Signal.strength(-120), 0);
      expect(Signal.strength(Signal.weakest), 0);
      expect(Signal.strength(Signal.strongest), 1);
      expect(Signal.strength(-20), 1);
    });

    test('stronger signals sit closer to the center', () {
      expect(Signal.radius(-50), lessThan(Signal.radius(-70)));
      expect(Signal.radius(-200), lessThanOrEqualTo(1));
      expect(Signal.radius(0), greaterThan(0));
    });

    test('the angle is stable and within a full turn', () {
      const id = 'AA:BB:CC:DD:EE:FF';
      expect(Signal.angle(id), Signal.angle(id));
      expect(Signal.angle(id), isNot(Signal.angle('AA:BB:CC:DD:EE:FE')));
      for (final id in ['', 'a', '6E400001-B5A3-F393-E0A9-E50E24DCCA9E']) {
        expect(Signal.angle(id), inInclusiveRange(0, 2 * math.pi));
      }
    });
  });

  group('hex', () {
    test('formats bytes', () {
      expect([0x4c, 0x00, 0x10].toHex(), '4C 00 10');
      expect([1, 2, 3, 4].toHex(max: 2), '01 02 …');
      expect(<int>[].toHex(), '');
    });

    test('parses common spellings', () {
      expect(parseHex('0a FF 3c'), [0x0a, 0xff, 0x3c]);
      expect(parseHex('0aff3c'), [0x0a, 0xff, 0x3c]);
      expect(parseHex('0x0a:ff'), [0x0a, 0xff]);
      expect(parseHex(''), <int>[]);
    });

    test('rejects invalid input', () {
      expect(parseHex('abc'), isNull);
      expect(parseHex('zz'), isNull);
    });
  });
}
