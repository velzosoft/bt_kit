import 'package:bt_radar/features/hunt/hunt_signal.dart';
import 'package:bt_radar/features/hunt/signal_trend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));

  test('searches until the first advertisement', () {
    final signal = HuntSignal(start);
    final reading = signal.readingAt(at(1000));
    expect(reading.status, HuntStatus.searching);
    expect(reading.strength, 0);
    expect(reading.silence, isNull);
  });

  test('is live once heard, with a smoothed signal', () {
    final signal = HuntSignal(start)
      ..add(-60, at(100))
      ..add(-60, at(200));
    final reading = signal.readingAt(at(300));
    expect(reading.status, HuntStatus.live);
    expect(reading.rssi, -60);
    expect(reading.strength, closeTo(40 / 65, 1e-9));
    expect(reading.silence, const Duration(milliseconds: 100));
  });

  test('is lost after 5 s without an advertisement', () {
    final signal = HuntSignal(start)..add(-60, at(0));
    expect(signal.readingAt(at(5000)).status, HuntStatus.live);
    final lost = signal.readingAt(at(5001));
    expect(lost.status, HuntStatus.lost);
    expect(lost.strength, 0);
    expect(lost.silence, const Duration(milliseconds: 5001));
  });

  test('is lost when nothing is heard within 5 s of starting', () {
    final signal = HuntSignal(start);
    expect(signal.readingAt(at(6000)).status, HuntStatus.lost);
  });

  test('ignores the unknown RSSI iOS reports', () {
    final signal = HuntSignal(start)..add(127, at(100));
    expect(signal.readingAt(at(200)).status, HuntStatus.searching);
  });

  test('reports the trend of the smoothed signal', () {
    final signal = HuntSignal(start);
    for (var ms = 0; ms <= 3000; ms += 100) {
      signal.add(ms < 1000 ? -80 : -55, at(ms));
    }
    expect(signal.readingAt(at(3000)).trend, Trend.warmer);
  });

  test('forgets everything on restart', () {
    final signal = HuntSignal(start)
      ..add(-50, at(0))
      ..restart(at(10000));
    expect(signal.readingAt(at(11000)).status, HuntStatus.searching);
  });
}
