import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../model/failure_tally.dart';
import '../model/lab_failure.dart';
import '../model/test_result.dart';
import 'lab_runner.dart';

/// Records a sequence of independent steps as checks: a failing step is
/// recorded and the next one still runs.
final class FlowSteps {
  FlowSteps(this.context, {required this.total});

  final LabContext context;
  final int total;
  final checks = <Check>[];
  final failures = FailureTally();

  /// Runs [body], whose result is the check's detail.
  Future<void> step(String name, Future<String> Function() body) async {
    if (context.isCancelled) return;
    context.report('$name…', checks.length / total);
    try {
      checks.add(Check(name, passed: true, detail: await body()));
    } on BluetoothException catch (e) {
      _failed(name, e);
    } on LabFailure catch (e) {
      _failed(name, e);
    } on TimeoutException catch (e) {
      _failed(name, e);
    }
  }

  String get summary =>
      '${checks.where((c) => c.passed).length} of ${checks.length} flows '
      'passed';

  void _failed(String name, Object error) {
    failures.add(name, error);
    checks.add(
      Check(name, passed: false, detail: FailureTally.describe(error)),
    );
  }
}
