import '../model/failure_tally.dart';
import '../model/test_result.dart';
import 'sample_summary.dart';

enum CyclePhase { connect, discover, read, write, readBack, disconnect, cycle }

/// What the connection cycle test measured, and its pass criteria.
final class CycleMetrics {
  CycleMetrics(this.planned);

  static const minSuccessRate = 0.995;

  final int planned;
  final failures = FailureTally();
  final _latencies = {for (final phase in CyclePhase.values) phase: <double>[]};
  var succeeded = 0;

  /// Attempts abandoned because the reference changed its address before
  /// they reached it; they are repeated and not counted.
  var addressChanges = 0;

  int get attempted => succeeded + failures.count;

  double get successRate => attempted == 0 ? 0 : succeeded / attempted;

  void addLatency(CyclePhase phase, Duration duration) =>
      _latencies[phase]!.add(duration.inMicroseconds / 1000);

  SampleSummary latency(CyclePhase phase) =>
      SampleSummary.of(_latencies[phase]!);

  List<Check> checks() => [
    Check(
      'All $planned cycles ran',
      passed: attempted >= planned,
      detail: '$attempted of $planned',
    ),
    Check(
      'At least ${_percent(minSuccessRate)} succeed',
      passed: attempted > 0 && successRate >= minSuccessRate,
      detail: '$succeeded of $attempted (${_percent(successRate)})',
    ),
  ];

  String get summary =>
      '$succeeded of $attempted cycles succeeded (${_percent(successRate)})'
      ' · cycle ${latency(CyclePhase.cycle).brief('ms')}';

  Map<String, Object?> toJson() => {
    'planned': planned,
    'attempted': attempted,
    'succeeded': succeeded,
    'failed': failures.count,
    'successRate': successRate,
    'addressChanges': addressChanges,
    'latencyMs': {
      for (final phase in CyclePhase.values)
        phase.name: latency(phase).toJson(),
    },
  };

  static String _percent(double rate) =>
      '${(rate * 100).toStringAsFixed(rate == 1 ? 0 : 1)}%';
}
