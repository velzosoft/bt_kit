import 'package:bt_radar/features/board/hue_ramp.dart';
import 'package:bt_radar/features/board/press_circle.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

void main() {
  group('HueRamp', () {
    test('runs from green to violet in 5 seconds, then stays', () {
      expect(HueRamp.hue(Duration.zero), 120);
      expect(HueRamp.hue(_ms(1000)), closeTo(78, 1e-9));
      expect(HueRamp.hue(_ms(2500)), closeTo(15, 1e-9));
      expect(HueRamp.hue(_ms(5000)), closeTo(270, 1e-9));
      expect(HueRamp.hue(_ms(8000)), closeTo(270, 1e-9));
    });

    test('treats a negative hold as no hold', () {
      expect(HueRamp.hue(_ms(-300)), 120);
    });

    test('gives the same colors as the board', () {
      expect(HueRamp.color(Duration.zero), const Color(0xff00ff00));
      expect(HueRamp.color(_ms(5000)), const Color(0xff8000ff));
    });

    test('reports its progress', () {
      expect(HueRamp.progress(Duration.zero), 0);
      expect(HueRamp.progress(_ms(2500)), 0.5);
      expect(HueRamp.progress(_ms(8000)), 1);
    });
  });

  group('PressGeometry', () {
    const maxRadius = 180.0;

    test('starts 24 across and reaches the canvas edge in 5 seconds', () {
      expect(PressGeometry.radius(Duration.zero, maxRadius: maxRadius), 12);
      expect(PressGeometry.radius(_ms(5000), maxRadius: maxRadius), maxRadius);
      expect(PressGeometry.radius(_ms(8000), maxRadius: maxRadius), maxRadius);
    });

    test('eases out: most of the growth comes first', () {
      final half = PressGeometry.radius(_ms(2500), maxRadius: maxRadius);
      expect(half, greaterThan((12 + maxRadius) / 2));
      expect(half, lessThan(maxRadius));
    });

    test('never shrinks below its start on a tiny canvas', () {
      expect(PressGeometry.radius(_ms(5000), maxRadius: 4), 12);
    });

    test('wobbles 3% at 2 Hz only at full size', () {
      expect(PressGeometry.wobbleAt(_ms(4000)), 1);
      expect(PressGeometry.wobbleAt(_ms(5125)), closeTo(1.03, 1e-9));
      expect(PressGeometry.wobbleAt(_ms(5375)), closeTo(0.97, 1e-9));
      expect(PressGeometry.wobbleAt(_ms(5500)), closeTo(1, 1e-9));
    });
  });
}
