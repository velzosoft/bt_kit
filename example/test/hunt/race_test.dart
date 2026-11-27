import 'package:bt_radar/features/hunt/party/found_detector.dart';
import 'package:bt_radar/features/hunt/party/race_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoundDetector', () {
    final start = DateTime(2026);
    DateTime at(int ms) => start.add(Duration(milliseconds: ms));

    test('needs a strong signal held for 1.5 s', () {
      final detector = FoundDetector();
      expect(detector.update(0.95, at(0)), isFalse);
      expect(detector.update(0.92, at(1000)), isFalse);
      expect(detector.update(0.93, at(1500)), isTrue);
    });

    test('starts over when the signal drops or is lost', () {
      final detector = FoundDetector();
      detector.update(0.95, at(0));
      expect(detector.update(0.5, at(1000)), isFalse);
      expect(detector.update(0.95, at(1100)), isFalse);
      expect(detector.update(null, at(2000)), isFalse);
      expect(detector.update(0.95, at(2600)), isFalse);
      expect(detector.update(0.95, at(4100)), isTrue);
    });
  });

  test('the countdown says 3, 2, 1, Go!', () {
    String? label(int ms) => Countdown.labelAt(Duration(milliseconds: ms));
    expect(label(-100), '3');
    expect(label(0), '3');
    expect(label(999), '3');
    expect(label(1000), '2');
    expect(label(2500), '1');
    expect(label(3000), 'Go!');
    expect(label(4000), isNull);
  });

  test('race times read in tenths of a second', () {
    expect(formatRaceTime(const Duration(milliseconds: 12345)), '12.3 s');
    expect(formatRaceTime(const Duration(milliseconds: 65049)), '1:05.0');
    expect(formatRaceTime(const Duration(seconds: -1)), '0.0 s');
  });
}
