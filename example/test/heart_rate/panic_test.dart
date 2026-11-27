import 'package:bt_radar/features/heart_rate/panic.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime(2026, 1, 1, 20);

DateTime _at(int seconds) => _start.add(Duration(seconds: seconds));

void main() {
  group('HeartRateBaseline', () {
    test('calibrates for the first 60 seconds of readings', () {
      final baseline = HeartRateBaseline();
      expect(baseline.isCalibrating, isTrue);
      expect(baseline.remainingAt(_at(0)), HeartRateBaseline.window);

      baseline.add(70, _at(0));
      expect(baseline.remainingAt(_at(15)), const Duration(seconds: 45));

      baseline
        ..add(80, _at(30))
        ..add(90, _at(59));
      expect(baseline.isCalibrating, isTrue);
      expect(baseline.value, isNull);
    });

    test('averages the window once a later reading arrives', () {
      final baseline = HeartRateBaseline()
        ..add(70, _at(0))
        ..add(80, _at(30))
        ..add(90, _at(59))
        ..add(200, _at(60));
      expect(baseline.isCalibrating, isFalse);
      expect(baseline.value, 80);
      expect(baseline.remainingAt(_at(61)), Duration.zero);
    });

    test('counts the window from the first reading', () {
      final baseline = HeartRateBaseline()
        ..add(60, _at(100))
        ..add(200, _at(150));
      expect(baseline.isCalibrating, isTrue);
      baseline.add(100, _at(160));
      expect(baseline.value, 130);
    });

    test('ignores readings without skin contact', () {
      final baseline = HeartRateBaseline()
        ..add(0, _at(0))
        ..add(60, _at(10))
        ..add(0, _at(20))
        ..add(80, _at(70));
      expect(baseline.value, 60);
    });

    test('stays fixed once known', () {
      final baseline = HeartRateBaseline()
        ..add(60, _at(0))
        ..add(60, _at(60))
        ..add(180, _at(61));
      expect(baseline.value, 60);
    });

    test('never reports negative time left', () {
      final baseline = HeartRateBaseline()..add(60, _at(0));
      expect(baseline.remainingAt(_at(90)), Duration.zero);
    });
  });

  group('Panic', () {
    test('measures the rise above baseline', () {
      final panic = Panic(90, 60);
      expect(panic.rise, 0.5);
      expect(panic.percent, 50);
      expect(panic.meter, 1);
    });

    test('fills the meter in proportion up to 50% above baseline', () {
      expect(Panic(75, 60).meter, closeTo(0.5, 1e-9));
      expect(Panic(120, 60).meter, 1);
    });

    test('is empty and negative below baseline', () {
      final panic = Panic(54, 60);
      expect(panic.percent, -10);
      expect(panic.meter, 0);
      expect(panic.level, PanicLevel.calm);
    });

    test('names the level', () {
      expect(Panic(105, 100).level, PanicLevel.calm);
      expect(Panic(110, 100).level, PanicLevel.uneasy);
      expect(Panic(125, 100).level, PanicLevel.tense);
      expect(Panic(140, 100).level, PanicLevel.panic);
    });
  });
}
