import 'dart:math';

import 'package:bt_radar/features/hunt/click_rate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('interval', () {
    test('runs from one click per 2 s to a near-continuous buzz', () {
      expect(ClickRate.interval(0), const Duration(seconds: 2));
      expect(ClickRate.interval(1), const Duration(milliseconds: 30));
    });

    test('is exponential: the middle is the geometric mean', () {
      final middle = ClickRate.interval(0.5).inMicroseconds / 1000;
      expect(middle, closeTo(sqrt(2000 * 30), 0.01));
    });

    test('speeds up steadily as the signal gets stronger', () {
      var previous = ClickRate.interval(0);
      for (var strength = 0.1; strength <= 1; strength += 0.1) {
        final next = ClickRate.interval(strength);
        expect(next, lessThan(previous));
        previous = next;
      }
    });

    test('clamps strengths outside 0 to 1', () {
      expect(ClickRate.interval(-0.5), ClickRate.interval(0));
      expect(ClickRate.interval(1.5), ClickRate.interval(1));
    });
  });

  test('the haptic gets heavier with strength', () {
    expect(ClickRate.hapticWeight(0), HapticWeight.selection);
    expect(ClickRate.hapticWeight(0.4), HapticWeight.light);
    expect(ClickRate.hapticWeight(0.7), HapticWeight.medium);
    expect(ClickRate.hapticWeight(0.95), HapticWeight.heavy);
  });

  test('vibrations are spaced out at high click rates', () {
    expect(
      ClickRate.vibrates(sinceLastVibration: const Duration(milliseconds: 30)),
      isFalse,
    );
    expect(
      ClickRate.vibrates(sinceLastVibration: ClickRate.hapticSpacing),
      isTrue,
    );
  });

  test('the volume rises from half to full', () {
    expect(ClickRate.volume(0), 0.5);
    expect(ClickRate.volume(1), 1);
    expect(ClickRate.volume(2), 1);
  });
}
