import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import 'filter_flows.dart';
import 'flow_steps.dart';
import 'lab_runner.dart';
import 'link_flows.dart';

/// Scan filters, then app connections, last values, explicit indications,
/// MTU state, connection priority, PHY, Services Changed and disconnect
/// reasons.
final class FiltersAndLinksRunner implements LabRunner {
  const FiltersAndLinksRunner();

  @override
  LabTestId get id => LabTestId.filtersAndLinks;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final steps = FlowSteps(context, total: 14);
    final notes = <String>[];
    final metrics = <String, Object?>{};
    await context.withOwnScans(() => FilterFlows(steps, notes).run());
    final connection = await context.connect();
    try {
      await LinkFlows(connection, steps, metrics).run();
    } finally {
      await quietly(connection.close);
    }
    return recorder.finish(
      summary: steps.summary,
      checks: steps.checks,
      metrics: metrics,
      failures: steps.failures,
      notes: notes,
    );
  }
}
