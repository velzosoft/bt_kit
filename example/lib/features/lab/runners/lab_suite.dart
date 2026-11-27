import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../../../bluetooth/scanner.dart';
import '../central/lab_target.dart';
import '../device_info.dart';
import '../model/failure_tally.dart';
import '../model/lab_plan.dart';
import '../model/lab_report.dart';
import '../model/lab_test_id.dart';
import '../model/test_progress.dart';
import '../model/test_result.dart';
import 'cancellation_runner.dart';
import 'connection_cycle_runner.dart';
import 'extras_runner.dart';
import 'gatt_flows_runner.dart';
import 'lab_runner.dart';
import 'notification_soak_runner.dart';
import 'filters_and_links_runner.dart';
import 'platform_runner.dart';
import 'scan_load_runner.dart';

/// Runs Lab tests one after another and collects a [LabReport]. The Lab
/// screen and the integration tests both use it.
final class LabSuite {
  LabSuite(this.plan, {this.scanner});

  static const runners = <LabTestId, LabRunner>{
    LabTestId.gattFlows: GattFlowsRunner(),
    LabTestId.connectionCycles: ConnectionCycleRunner(),
    LabTestId.notificationSoak: NotificationSoakRunner(),
    LabTestId.cancellation: CancellationRunner(),
    LabTestId.scanLoad: ScanLoadRunner(),
    LabTestId.filtersAndLinks: FiltersAndLinksRunner(),
    LabTestId.platform: PlatformRunner(),
    LabTestId.extras: ExtrasRunner(),
  };

  final LabPlan plan;

  /// The app's shared scan, which tests pause to scan with other options.
  final Scanner? scanner;

  /// Runs [tests] in the order of [LabTestId.values]. [target] is required
  /// by every test but the scan load.
  ///
  /// Cancelling [cancelToken] stops the run; cancelling the token passed to
  /// [onStart] skips to the next test.
  Future<LabReport> run(
    Set<LabTestId> tests, {
    LabTarget? target,
    CancelToken? cancelToken,
    void Function(LabTestId id, CancelToken skip)? onStart,
    void Function(LabTestId id, TestProgress progress)? onProgress,
    void Function(TestResult result)? onResult,
  }) async {
    final token = cancelToken ?? CancelToken();
    final startedAt = DateTime.now();
    final reference = target == null
        ? const <String, Object?>{}
        : await _describe(target, token);
    final results = <TestResult>[];
    for (final id in LabTestId.values.where(tests.contains)) {
      if (token.isCancelled) break;
      final skip = CancelToken();
      unawaited(token.whenCancelled.then(skip.cancel));
      onStart?.call(id, skip);
      final context = LabContext(
        plan: plan,
        target: target,
        cancelToken: skip,
        onProgress: (progress) => onProgress?.call(id, progress),
        scanner: scanner,
      );
      final result = await _run(id, context);
      results.add(result);
      onResult?.call(result);
    }
    return LabReport(
      plan: plan,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      device: DeviceInfo.describe(),
      reference: {
        ...reference,
        if (target != null) 'addressChanges': target.addressChanges,
      },
      results: results,
    );
  }

  Future<TestResult> _run(LabTestId id, LabContext context) async {
    final startedAt = DateTime.now();
    if (id.needsReference && context.target == null) {
      return _notRun(id, context, startedAt, 'No reference peripheral');
    }
    try {
      return await runners[id]!.run(context);
    } on Object catch (error) {
      return _notRun(id, context, startedAt, FailureTally.describe(error));
    }
  }

  TestResult _notRun(
    LabTestId id,
    LabContext context,
    DateTime startedAt,
    String reason,
  ) {
    final cancelled = context.isCancelled;
    return TestResult(
      id: id,
      criterion: id.criterion(plan),
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      summary: cancelled ? 'Cancelled' : 'Could not run: $reason',
      cancelled: cancelled,
      error: cancelled ? null : reason,
    );
  }

  /// What the reference says about itself, read once before the tests.
  Future<Map<String, Object?>> _describe(
    LabTarget target,
    CancelToken token,
  ) async {
    final context = LabContext(
      plan: plan,
      target: target,
      cancelToken: token,
      onProgress: (_) {},
    );
    try {
      final connection = await context.connect();
      try {
        return {'info': await connection.readInfo()};
      } finally {
        await quietly(connection.close);
      }
    } on Exception catch (error) {
      return {'probeError': FailureTally.describe(error)};
    }
  }
}
