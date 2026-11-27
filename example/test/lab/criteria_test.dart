import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/lab/metrics/cancellation_metrics.dart';
import 'package:bt_radar/features/lab/metrics/cycle_metrics.dart';
import 'package:bt_radar/features/lab/metrics/scan_load_metrics.dart';
import 'package:bt_radar/features/lab/metrics/soak_metrics.dart';
import 'package:bt_radar/features/lab/model/test_result.dart';
import 'package:bt_radar/features/lab/profile/stream_packet.dart';
import 'package:flutter_test/flutter_test.dart';

bool allPass(List<Check> checks) => checks.every((c) => c.passed);

Check named(List<Check> checks, String prefix) =>
    checks.firstWhere((c) => c.name.startsWith(prefix));

void main() {
  group('connection cycles', () {
    CycleMetrics cycles({required int succeeded, required int failed}) {
      final metrics = CycleMetrics(succeeded + failed)..succeeded = succeeded;
      for (var i = 0; i < failed; i++) {
        metrics.failures.add(
          'connect',
          OperationTimeoutException('connect', const Duration(seconds: 10)),
        );
      }
      return metrics;
    }

    test('498 of 500 passes the 99.5% bar', () {
      expect(allPass(cycles(succeeded: 498, failed: 2).checks()), isTrue);
    });

    test('497 of 500 fails it', () {
      final checks = cycles(succeeded: 497, failed: 3).checks();
      expect(named(checks, 'At least').passed, isFalse);
    });

    test('a run cut short fails', () {
      final metrics = CycleMetrics(500)..succeeded = 100;
      expect(named(metrics.checks(), 'All 500').passed, isFalse);
    });

    test('failures are counted by type and phase', () {
      final json = cycles(succeeded: 1, failed: 2).failures.toJson();
      expect(json['byType'], {'OperationTimeoutException': 2});
      expect(json['byPhase'], {'connect': 2});
    });
  });

  group('notification soak', () {
    SoakMetrics soak({
      int count = 500,
      int intervalMicros = 20000,
      Set<int> skip = const {},
      bool completed = true,
    }) {
      final metrics = SoakMetrics(
        rateHz: 50,
        duration: const Duration(seconds: 10),
      )..completed = completed;
      for (var i = 0; i < count; i++) {
        if (skip.contains(i)) continue;
        metrics.add(
          StreamPacket(i, i * intervalMicros),
          arrivalMicros: 1000 + i * intervalMicros,
        );
      }
      return metrics;
    }

    test('every value in order at 50 Hz passes', () {
      final metrics = soak();
      expect(metrics.deliveredRateHz, closeTo(50, 0.01));
      expect(allPass(metrics.checks()), isTrue);
    });

    test('a lost value fails', () {
      final checks = soak(skip: {250}).checks();
      expect(named(checks, 'No lost').passed, isFalse);
    });

    test('a value out of order fails', () {
      final metrics = soak()
        ..add(const StreamPacket(500, 0), arrivalMicros: 0)
        ..add(const StreamPacket(502, 0), arrivalMicros: 0)
        ..add(const StreamPacket(501, 0), arrivalMicros: 0);
      expect(named(metrics.checks(), 'No out-of-order').passed, isFalse);
    });

    test('a slow stream fails the rate', () {
      final checks = soak(intervalMicros: 25000).checks();
      expect(named(checks, 'Delivered').passed, isFalse);
    });

    test('a soak that stopped early fails', () {
      final metrics = soak()..linkError = 'DisconnectedException';
      expect(named(metrics.checks(), 'Ran for').passed, isFalse);
      expect(named(soak(completed: false).checks(), 'Ran for').passed, false);
    });
  });

  group('scan load', () {
    const mib = 1024 * 1024;

    ScanLoadMetrics scan({required int leakPerResult}) {
      final metrics = ScanLoadMetrics(target: 10000);
      for (var n = 0; n <= 10000; n += metrics.sampleEvery) {
        metrics.received = n;
        metrics.memory.add(results: n, bytes: 300 * mib + n * leakPerResult);
      }
      return metrics;
    }

    test('flat memory passes', () {
      expect(allPass(scan(leakPerResult: 0).checks()), isTrue);
    });

    test('a 1 KB leak per result fails', () {
      final checks = scan(leakPerResult: 1024).checks();
      expect(named(checks, 'Memory').passed, isFalse);
    });

    test('too few results fails', () {
      final metrics = ScanLoadMetrics(target: 10000)
        ..received = 4000
        ..stopReason = 'Only 4000 results in 30 minutes';
      expect(named(metrics.checks(), 'Received').passed, isFalse);
    });

    test('reports a JNI reference field on Android only', () {
      final metrics = scan(leakPerResult: 0);
      final android = metrics.toJson(platform: 'android');
      expect(android['jniGlobalReferences'], isA<Map<String, Object?>>());
      expect(
        (android['jniGlobalReferences']! as Map)['howToMeasure'],
        contains('dumpsys meminfo'),
      );
      expect(metrics.toJson(platform: 'ios')['jniGlobalReferences'], isNull);
    });
  });

  group('cancellation and timeouts', () {
    CancellationMetrics clean() {
      final metrics = CancellationMetrics(bursts: 2, burstSize: 3)
        ..completedBursts = 2;
      for (final outcome in [
        BurstOutcome.succeeded,
        BurstOutcome.cancelled,
        BurstOutcome.timedOut,
      ]) {
        metrics.add(outcome);
      }
      metrics
        ..addCancelLatency(const Duration(milliseconds: 1))
        ..addRecovery(const Duration(milliseconds: 80))
        ..addRecovery(const Duration(milliseconds: 90));
      return metrics;
    }

    test('a run without stalls or overlaps passes', () {
      expect(allPass(clean().checks()), isTrue);
    });

    test('a platform rejection is an overlap', () {
      final checks = (clean()..add(BurstOutcome.rejected)).checks();
      expect(named(checks, 'Requests never overlapped').passed, isFalse);
    });

    test('a wrong value is an overlap', () {
      final checks = (clean()..add(BurstOutcome.crossTalk)).checks();
      expect(named(checks, 'Requests never overlapped').passed, isFalse);
    });

    test('a stalled operation fails', () {
      final checks = (clean()..add(BurstOutcome.stalled)).checks();
      expect(named(checks, 'Every operation settled').passed, isFalse);
    });

    test('a failed recovery fails', () {
      final checks = (clean()..failedRecoveries = 1).checks();
      expect(named(checks, 'The queue recovered').passed, isFalse);
    });

    test('a slow cancellation fails', () {
      final checks =
          (clean()..addCancelLatency(const Duration(milliseconds: 150)))
              .checks();
      expect(named(checks, 'Cancellation took effect').passed, isFalse);
    });

    test('a dropped link fails', () {
      final checks = (clean()..reconnects = 1).checks();
      expect(named(checks, 'The link stayed up').passed, isFalse);
    });
  });
}
