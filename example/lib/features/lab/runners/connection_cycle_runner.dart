import 'dart:convert';

import 'package:bt_kit/bt_kit.dart';

import '../central/reference_characteristics.dart';
import '../metrics/cycle_metrics.dart';
import '../model/lab_failure.dart';
import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import '../profile/reference_profile.dart';
import 'lab_runner.dart';

/// Connect, discover, read, write, read back and disconnect, over and over.
final class ConnectionCycleRunner implements LabRunner {
  const ConnectionCycleRunner();

  @override
  LabTestId get id => LabTestId.connectionCycles;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final plan = context.plan;
    final metrics = CycleMetrics(plan.cycles);
    while (metrics.attempted < plan.cycles && !context.isCancelled) {
      await _Cycle(context, metrics).run();
      context.report(metrics.summary, metrics.attempted / plan.cycles);
      await context.pause(plan.cyclePause);
    }
    return recorder.finish(
      summary: metrics.summary,
      checks: metrics.checks(),
      metrics: metrics.toJson(),
      parameters: {
        'cycles': plan.cycles,
        'connectTimeoutSeconds': plan.connectTimeout.inSeconds,
        'pauseMs': plan.cyclePause.inMilliseconds,
      },
      failures: metrics.failures,
      notes: [
        if (metrics.addressChanges > 0)
          'The reference changed its address ${metrics.addressChanges} '
              'times; those attempts were repeated, not counted.',
      ],
    );
  }
}

final class _Cycle {
  _Cycle(this.context, this.metrics);

  /// More address changes than this mean several references are nearby,
  /// not one that rotates its address.
  static const _maxAddressChanges = 10;

  final LabContext context;
  final CycleMetrics metrics;
  var _phase = CyclePhase.connect;

  Peripheral get _peripheral => context.reference.peripheral;

  Future<void> run() async {
    final index = metrics.attempted;
    final cycle = Stopwatch()..start();
    try {
      await _timed(
        CyclePhase.connect,
        () => _peripheral.connect(
          timeout: context.plan.connectTimeout,
          cancelToken: context.cancelToken,
        ),
      );
      await _timed(
        CyclePhase.discover,
        () => _peripheral.discoverServices(cancelToken: context.cancelToken),
      );
      final profile = ReferenceCharacteristics.of(_peripheral);
      final fixed = await _timed(
        CyclePhase.read,
        () => profile[ReferenceCharacteristic.fixedValue].read(
          cancelToken: context.cancelToken,
        ),
      );
      ValueMismatch.check('Fixed value', fixed, ReferenceProfile.fixedValue);
      final echo = profile[ReferenceCharacteristic.echo];
      final payload = utf8.encode('cycle $index');
      await _timed(
        CyclePhase.write,
        () => echo.write(payload, cancelToken: context.cancelToken),
      );
      final back = await _timed(
        CyclePhase.readBack,
        () => echo.read(cancelToken: context.cancelToken),
      );
      ValueMismatch.check('Echo', back, payload);
      await _timed(CyclePhase.disconnect, _peripheral.disconnect);
      metrics.addLatency(CyclePhase.cycle, cycle.elapsed);
      metrics.succeeded++;
    } on BluetoothException catch (e) {
      await _failed(e);
    } on LabFailure catch (e) {
      await _failed(e);
    }
  }

  Future<T> _timed<T>(CyclePhase phase, Future<T> Function() action) async {
    _phase = phase;
    final clock = Stopwatch()..start();
    final result = await action();
    metrics.addLatency(phase, clock.elapsed);
    return result;
  }

  Future<void> _failed(Object error) async {
    await quietly(_peripheral.disconnect);
    if (context.isCancelled) return;
    if (_phase == CyclePhase.connect &&
        metrics.addressChanges < _maxAddressChanges &&
        await context.reference.relocate()) {
      metrics.addressChanges++;
      return;
    }
    metrics.failures.add(
      _phase.name,
      error,
      context: '#${metrics.attempted + 1}',
    );
  }
}
