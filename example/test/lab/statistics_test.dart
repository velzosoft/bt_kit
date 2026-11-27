import 'package:bt_radar/features/lab/metrics/delay_variation.dart';
import 'package:bt_radar/features/lab/metrics/memory_trend.dart';
import 'package:bt_radar/features/lab/metrics/sample_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SampleSummary', () {
    test('uses nearest-rank percentiles', () {
      final summary = SampleSummary.of([for (var i = 1; i <= 100; i++) i]);
      expect(summary.count, 100);
      expect(summary.min, 1);
      expect(summary.max, 100);
      expect(summary.mean, 50.5);
      expect(summary.p50, 50);
      expect(summary.p95, 95);
      expect(summary.p99, 99);
    });

    test('ignores input order', () {
      final summary = SampleSummary.of([5, 1, 3]);
      expect(summary.p50, 3);
      expect(summary.min, 1);
    });

    test('a single sample is every percentile', () {
      final summary = SampleSummary.of([7.5]);
      expect([summary.p50, summary.p99, summary.max], [7.5, 7.5, 7.5]);
    });

    test('is empty without samples', () {
      expect(SampleSummary.of(const <int>[]).toJson(), {'count': 0});
      expect(SampleSummary.empty.brief('ms'), 'no samples');
    });

    test('rounds to two decimals in JSON', () {
      expect(SampleSummary.of([1.23456]).toJson()['p50'], 1.23);
    });
  });

  group('DelayVariation', () {
    test('removes a constant delay, clock offset and drift', () {
      final delay = DelayVariation();
      for (var i = 0; i < 3000; i++) {
        final sent = i * 20000;
        final drift = (sent * 40e-6).round();
        delay.add(sentMicros: sent, receivedMicros: 5000000 + sent + drift);
      }
      expect(delay.driftPpm, closeTo(40, 0.5));
      expect(delay.millis().max, lessThan(0.01));
    });

    test('measures a late value against the fastest', () {
      final delay = DelayVariation();
      for (var i = 0; i < 1000; i++) {
        final late = i == 500 ? 12000 : 0;
        delay.add(sentMicros: i * 20000, receivedMicros: i * 20000 + late);
      }
      final variation = delay.millis();
      expect(variation.max, closeTo(12, 0.1));
      expect(variation.p50, closeTo(0, 0.1));
    });

    test('needs two values', () {
      final delay = DelayVariation()..add(sentMicros: 0, receivedMicros: 10);
      expect(delay.driftPpm, isNull);
      expect(delay.millis().count, 0);
    });
  });

  group('MemoryTrend', () {
    const mib = 1024 * 1024;

    test('noise around a flat line is little growth', () {
      final trend = MemoryTrend(warmup: 2000);
      for (var results = 0; results <= 10000; results += 200) {
        final noise = (results ~/ 200).isEven ? 0 : 2 * mib;
        trend.add(results: results, bytes: 200 * mib + noise);
      }
      expect(trend.growthBytes!.abs(), lessThanOrEqualTo(2 * mib));
    });

    test('a leak grows with the results', () {
      final trend = MemoryTrend(warmup: 2000);
      for (var results = 0; results <= 10000; results += 200) {
        trend.add(results: results, bytes: 200 * mib + results * 1024);
      }
      expect(trend.bytesPerResult, closeTo(1024, 1));
      expect(trend.growthBytes, greaterThan(5 * mib));
    });

    test('ignores the warm-up', () {
      final trend = MemoryTrend(warmup: 1000)
        ..add(results: 0, bytes: 100 * mib)
        ..add(results: 500, bytes: 180 * mib);
      for (var results = 1000; results <= 2000; results += 100) {
        trend.add(results: results, bytes: 200 * mib);
      }
      expect(trend.growthBytes, 0);
    });

    test('needs four samples after warm-up', () {
      final trend = MemoryTrend(warmup: 0)
        ..add(results: 0, bytes: 1)
        ..add(results: 1, bytes: 2)
        ..add(results: 2, bytes: 3);
      expect(trend.growthBytes, isNull);
    });
  });
}
