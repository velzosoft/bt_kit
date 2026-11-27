import 'failure_tally.dart';
import 'lab_test_id.dart';

enum TestOutcome { passed, failed, cancelled, error }

/// One pass criterion of a test and how the run measured against it.
final class Check {
  const Check(this.name, {required this.passed, required this.detail});

  final String name;
  final bool passed;
  final String detail;

  Map<String, Object?> toJson() => {
    'name': name,
    'passed': passed,
    'detail': detail,
  };
}

final class TestResult {
  TestResult({
    required this.id,
    required this.criterion,
    required this.startedAt,
    required this.finishedAt,
    required this.summary,
    this.parameters = const {},
    this.checks = const [],
    this.metrics = const {},
    this.failures,
    this.notes = const [],
    this.cancelled = false,
    this.error,
  });

  final LabTestId id;
  final String criterion;
  final DateTime startedAt;
  final DateTime finishedAt;

  /// One line for the screen, such as "498 of 500 cycles (99.6%)".
  final String summary;
  final Map<String, Object?> parameters;
  final List<Check> checks;
  final Map<String, Object?> metrics;
  final FailureTally? failures;
  final List<String> notes;
  final bool cancelled;

  /// Why the test could not run at all.
  final String? error;

  TestOutcome get outcome {
    if (error != null) return TestOutcome.error;
    if (cancelled) return TestOutcome.cancelled;
    final passed = checks.isNotEmpty && checks.every((c) => c.passed);
    return passed ? TestOutcome.passed : TestOutcome.failed;
  }

  Duration get duration => finishedAt.difference(startedAt);

  Map<String, Object?> toJson() => {
    'id': id.name,
    'title': id.title,
    'outcome': outcome.name,
    'criterion': criterion,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'durationSeconds': duration.inMilliseconds / 1000,
    'summary': summary,
    'parameters': parameters,
    'checks': [for (final check in checks) check.toJson()],
    'metrics': metrics,
    if (failures case final failures?) 'failures': failures.toJson(),
    if (notes.isNotEmpty) 'notes': notes,
    if (error != null) 'error': error,
  };
}
