import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import 'extra_flows.dart';
import 'flow_steps.dart';
import 'lab_runner.dart';

/// The smaller features: scan settings, connecting with an MTU, chunked
/// writes, included services, GATT cache refresh, the adapter name,
/// advertising updates and periodic advertising.
final class ExtrasRunner implements LabRunner {
  const ExtrasRunner();

  @override
  LabTestId get id => LabTestId.extras;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final steps = FlowSteps(context, total: ExtraFlows.stepCount);
    final metrics = <String, Object?>{};
    await context.withOwnScans(() => ExtraFlows(steps, metrics).run());
    return recorder.finish(
      summary: steps.summary,
      checks: steps.checks,
      metrics: metrics,
      failures: steps.failures,
    );
  }
}
