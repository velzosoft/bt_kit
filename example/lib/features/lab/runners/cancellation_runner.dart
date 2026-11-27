import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bt_kit/bt_kit.dart';

import '../central/lab_connection.dart';
import '../metrics/cancellation_metrics.dart';
import '../model/lab_failure.dart';
import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import '../profile/reference_profile.dart';
import 'burst_operation.dart';
import 'lab_runner.dart';

/// Bursts of queued operations, some cancelled at random moments and some
/// with timeouts shorter than a round trip. After each burst, a write and
/// two reads must complete promptly with the right values: the queue never
/// stalls, and a late answer never reaches the wrong request.
final class CancellationRunner implements LabRunner {
  const CancellationRunner({this.seed});

  /// Fixes the random choices, to repeat a run exactly.
  final int? seed;

  @override
  LabTestId get id => LabTestId.cancellation;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final plan = context.plan;
    final seed = this.seed ?? Random().nextInt(1 << 31);
    final metrics = CancellationMetrics(
      bursts: plan.bursts,
      burstSize: plan.burstSize,
    );
    var connection = await context.connect();
    try {
      final random = Random(seed);
      for (var burst = 0; burst < plan.bursts; burst++) {
        if (context.isCancelled) break;
        final operations = [
          for (var i = 0; i < plan.burstSize; i++)
            BurstOperation.random(random),
        ];
        await Future.wait([
          for (final operation in operations)
            operation.run(connection, metrics),
        ]);
        if (context.isCancelled) break;
        await _recover(connection, burst, metrics);
        metrics.completedBursts++;
        if (!connection.peripheral.isConnected) {
          metrics.reconnects++;
          connection = await context.connect();
        }
        context.report(metrics.summary, (burst + 1) / plan.bursts);
      }
    } finally {
      await quietly(connection.close);
    }
    return recorder.finish(
      summary: metrics.summary,
      checks: metrics.checks(),
      metrics: metrics.toJson(),
      parameters: {
        'bursts': plan.bursts,
        'burstSize': plan.burstSize,
        'seed': seed,
        'shortTimeoutMs':
            '${BurstOperation.shortTimeouts.start}–'
            '${BurstOperation.shortTimeouts.end}',
        'cancelAfterMs': '0–${BurstOperation.maxCancelDelay.inMilliseconds}',
      },
      failures: metrics.failures,
    );
  }

  /// A write and two reads issued right after the burst, each within the
  /// recovery deadline and with the expected value.
  static Future<void> _recover(
    LabConnection connection,
    int burst,
    CancellationMetrics metrics,
  ) async {
    const deadline = CancellationMetrics.recoveryDeadline;
    final clock = Stopwatch()..start();
    try {
      final echo = connection[ReferenceCharacteristic.echo];
      final token = utf8.encode('burst $burst');
      await echo.write(token, timeout: deadline);
      ValueMismatch.check('Echo', await echo.read(timeout: deadline), token);
      ValueMismatch.check(
        'Fixed value',
        await connection[ReferenceCharacteristic.fixedValue].read(
          timeout: deadline,
        ),
        ReferenceProfile.fixedValue,
      );
      if (clock.elapsed > deadline) {
        throw DeadlineExceeded('took ${clock.elapsed.inMilliseconds} ms');
      }
      metrics.addRecovery(clock.elapsed);
    } on BluetoothException catch (e) {
      metrics
        ..failedRecoveries += 1
        ..failures.add('recovery', e, context: 'burst $burst');
    } on LabFailure catch (e) {
      metrics
        ..failedRecoveries += 1
        ..failures.add('recovery', e, context: 'burst $burst');
    }
  }
}
