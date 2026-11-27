import 'dart:async';
import 'dart:io';

import 'package:bt_kit/bt_kit.dart';

import '../../../bluetooth/scanner.dart';
import '../metrics/scan_load_metrics.dart';
import '../model/failure_tally.dart';
import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import 'lab_runner.dart';

/// Thousands of scan results through the app's shared scan, sampling the
/// process's resident memory as they arrive.
final class ScanLoadRunner implements LabRunner {
  const ScanLoadRunner();

  @override
  LabTestId get id => LabTestId.scanLoad;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final plan = context.plan;
    final metrics = ScanLoadMetrics(target: plan.scanResults);
    final clock = Stopwatch()..start();
    final done = Completer<void>();
    void stop([String? reason]) {
      metrics.stopReason ??= reason;
      if (!done.isCompleted) done.complete();
    }

    void sample() => metrics.memory.add(
      results: metrics.received,
      bytes: ProcessInfo.currentRss,
    );

    sample();
    final subscription = BtKit.instance
        .scan(Scanner.options)
        .listen(
          (_) {
            metrics.received++;
            if (metrics.received % metrics.sampleEvery == 0) {
              sample();
              metrics.elapsed = clock.elapsed;
              context.report(
                metrics.summary,
                metrics.received / metrics.target,
              );
            }
            if (metrics.received >= metrics.target) stop();
          },
          onError: (Object error) => stop(FailureTally.describe(error)),
          onDone: () => stop('The scan ended'),
        );
    final limit = Timer(
      plan.scanTimeLimit,
      () => stop(
        'Only ${metrics.received} results in '
        '${plan.scanTimeLimit.inMinutes} minutes',
      ),
    );
    unawaited(context.cancelToken.whenCancelled.then((_) => stop()));
    await done.future;
    limit.cancel();
    await subscription.cancel();
    metrics.elapsed = clock.elapsed;
    return recorder.finish(
      summary: metrics.summary,
      checks: metrics.checks(),
      metrics: metrics.toJson(platform: Platform.operatingSystem),
      parameters: {
        'results': plan.scanResults,
        'timeLimitSeconds': plan.scanTimeLimit.inSeconds,
        'scanOptions': 'allowDuplicates, lowLatency (the app-wide scan)',
      },
      notes: [
        'Memory is the resident set size of the whole process '
            '(ProcessInfo.currentRss).',
        if (Platform.isAndroid)
          'JNI global references cannot be read in the app: compare '
              '`adb shell dumpsys meminfo dev.btkit.bt_radar` before and '
              'after, and fill in metrics.jniGlobalReferences.',
        if (Platform.isIOS)
          'For native allocations, profile with Xcode Instruments '
              '(Allocations, Leaks).',
        'The ≥ 500 results per second budget depends on the devices '
            'nearby; resultsPerSecond is for reference only.',
      ],
    );
  }
}
