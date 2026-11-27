import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import 'flow_steps.dart';
import 'lab_runner.dart';
import 'platform_flows.dart';

/// The platform features that work with the reference alone: bonding,
/// background scans, connection events, distance, audio state and Classic
/// discovery. RFCOMM and MFi sessions need other hardware.
final class PlatformRunner implements LabRunner {
  const PlatformRunner();

  @override
  LabTestId get id => LabTestId.platform;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final steps = FlowSteps(context, total: PlatformFlows.stepCount);
    final metrics = <String, Object?>{};
    await context.withOwnScans(() => PlatformFlows(steps, metrics).run());
    return recorder.finish(
      summary: steps.summary,
      checks: steps.checks,
      metrics: metrics,
      failures: steps.failures,
    );
  }
}
