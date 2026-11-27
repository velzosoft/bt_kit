import 'dart:convert';

import 'lab_plan.dart';
import 'test_result.dart';

/// Everything one Lab run measured, encodable as JSON.
final class LabReport {
  LabReport({
    required this.plan,
    required this.startedAt,
    required this.finishedAt,
    required this.device,
    required this.results,
    this.reference = const {},
  });

  static const schema = 'bt_kit.lab/1';

  final LabPlan plan;
  final DateTime startedAt;
  final DateTime finishedAt;

  /// The phone that ran the tests (the central).
  final Map<String, Object?> device;

  /// The reference peripheral, as its Info characteristic describes itself.
  final Map<String, Object?> reference;
  final List<TestResult> results;

  bool get passed =>
      results.isNotEmpty &&
      results.every((r) => r.outcome == TestOutcome.passed);

  int count(TestOutcome outcome) =>
      results.where((r) => r.outcome == outcome).length;

  Map<String, Object?> toJson() => {
    'schema': schema,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'plan': plan.toJson(),
    'device': device,
    'reference': reference,
    'summary': {
      'allPassed': passed,
      for (final outcome in TestOutcome.values) outcome.name: count(outcome),
    },
    'results': [for (final result in results) result.toJson()],
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Such as `bt_kit-lab-full-20261125-143005.json`.
  String get fileName {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = startedAt;
    return 'bt_kit-lab-${plan.mode.name}-${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
  }
}
