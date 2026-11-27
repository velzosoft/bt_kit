import '../model/failure_tally.dart';
import '../model/test_result.dart';
import 'sample_summary.dart';

/// How each queued operation of a burst ended.
enum BurstOutcome {
  succeeded,
  cancelled,
  timedOut,

  /// The platform refused a request because another was still in flight.
  rejected,

  /// A read returned another characteristic's value.
  crossTalk,
  disconnected,
  failed,

  /// Never settled.
  stalled,
}

/// What the cancellation and timeout test measured, and its pass criteria.
final class CancellationMetrics {
  CancellationMetrics({required this.bursts, required this.burstSize});

  static const recoveryDeadline = Duration(seconds: 3);
  static const maxCancelLatency = Duration(milliseconds: 100);

  final int bursts;
  final int burstSize;
  final outcomes = {for (final o in BurstOutcome.values) o: 0};

  /// Failures of operations that had neither a short timeout nor a
  /// cancellation, and of the checks after each burst.
  final failures = FailureTally();
  final _cancelLatencies = <double>[];
  final _recoveries = <double>[];
  var completedBursts = 0;
  var failedRecoveries = 0;
  var unexpectedTimeouts = 0;
  var reconnects = 0;

  void add(BurstOutcome outcome) => outcomes[outcome] = outcomes[outcome]! + 1;

  void addCancelLatency(Duration latency) =>
      _cancelLatencies.add(latency.inMicroseconds / 1000);

  void addRecovery(Duration latency) =>
      _recoveries.add(latency.inMicroseconds / 1000);

  SampleSummary get cancelLatency => SampleSummary.of(_cancelLatencies);

  SampleSummary get recovery => SampleSummary.of(_recoveries);

  int get _overlaps =>
      outcomes[BurstOutcome.rejected]! + outcomes[BurstOutcome.crossTalk]!;

  List<Check> checks() => [
    Check(
      'Every operation settled',
      passed: outcomes[BurstOutcome.stalled] == 0 && unexpectedTimeouts == 0,
      detail:
          '${outcomes[BurstOutcome.stalled]} stalled, $unexpectedTimeouts '
          'timed out without a short timeout',
    ),
    Check(
      'The queue recovered after every burst within '
      '${recoveryDeadline.inSeconds} s',
      passed: completedBursts > 0 && failedRecoveries == 0,
      detail:
          '$failedRecoveries of $completedBursts recoveries failed · '
          '${recovery.brief('ms')}',
    ),
    Check(
      'Requests never overlapped',
      passed: _overlaps == 0,
      detail:
          '${outcomes[BurstOutcome.rejected]} rejected by the platform, '
          '${outcomes[BurstOutcome.crossTalk]} wrong values',
    ),
    Check(
      'Cancellation took effect within ${maxCancelLatency.inMilliseconds} ms',
      passed: cancelLatency.max <= maxCancelLatency.inMilliseconds,
      detail: cancelLatency.brief('ms'),
    ),
    Check(
      'The link stayed up',
      passed: outcomes[BurstOutcome.disconnected] == 0 && reconnects == 0,
      detail:
          '${outcomes[BurstOutcome.disconnected]} operations failed by '
          'disconnection, $reconnects reconnects',
    ),
  ];

  String get summary =>
      '$completedBursts of $bursts bursts · '
      '${outcomes[BurstOutcome.cancelled]} cancelled · '
      '${outcomes[BurstOutcome.timedOut]} timed out · $_overlaps overlaps';

  Map<String, Object?> toJson() => {
    'bursts': bursts,
    'burstSize': burstSize,
    'completedBursts': completedBursts,
    'outcomes': {
      for (final MapEntry(:key, :value) in outcomes.entries) key.name: value,
    },
    'unexpectedTimeouts': unexpectedTimeouts,
    'failedRecoveries': failedRecoveries,
    'reconnects': reconnects,
    'cancelLatencyMs': cancelLatency.toJson(),
    'recoveryMs': recovery.toJson(),
  };
}
