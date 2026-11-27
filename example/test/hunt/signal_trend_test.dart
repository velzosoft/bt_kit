import 'package:bt_radar/features/hunt/signal_trend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));

  TrendTracker track(Map<int, double> samples) {
    final tracker = TrendTracker();
    for (final MapEntry(key: ms, value: rssi) in samples.entries) {
      tracker.add(at(ms), rssi);
    }
    return tracker;
  }

  test('is steady until it has 2 s of history', () {
    final tracker = track({0: -80, 1500: -60});
    expect(tracker.trendAt(at(1500)), Trend.steady);
  });

  test('is warmer when the signal rose by 2 dB or more', () {
    final tracker = track({0: -80, 1000: -79, 2000: -78});
    expect(tracker.trendAt(at(2000)), Trend.warmer);
  });

  test('is colder when the signal fell by 2 dB or more', () {
    final tracker = track({0: -60, 1000: -61, 2000: -63});
    expect(tracker.trendAt(at(2000)), Trend.colder);
  });

  test('is steady for smaller changes', () {
    final tracker = track({0: -70, 1000: -69, 2000: -68.5});
    expect(tracker.trendAt(at(2000)), Trend.steady);
  });

  test('compares with the reading from about 2 s ago, not the oldest', () {
    final tracker = track({0: -90, 1000: -70, 3000: -69});
    expect(tracker.trendAt(at(3000)), Trend.steady);
  });

  test('starts over when cleared', () {
    final tracker = track({0: -80, 2000: -60})..clear();
    expect(tracker.trendAt(at(2000)), Trend.steady);
  });
}
