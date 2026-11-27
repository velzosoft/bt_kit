import '../model/test_result.dart';
import '../profile/stream_packet.dart';
import 'delay_variation.dart';
import 'sample_summary.dart';
import 'sequence_tracker.dart';

/// What the notification soak measured, and its pass criteria.
final class SoakMetrics {
  SoakMetrics({required this.rateHz, required this.duration});

  /// The delivered rate may fall this far below the requested one.
  static const minRateRatio = 0.95;

  final int rateHz;
  final Duration duration;
  final sequence = SequenceTracker();
  final delay = DelayVariation();
  final _intervals = <double>[];
  int? _firstArrival;
  int? _lastArrival;
  var malformed = 0;

  /// Whether the soak lasted its full duration.
  var completed = false;

  /// Why the subscription ended early, if it did.
  String? linkError;

  void add(StreamPacket packet, {required int arrivalMicros}) {
    sequence.add(packet.sequence);
    delay.add(
      sentMicros: packet.timestampMicros,
      receivedMicros: arrivalMicros,
    );
    if (_lastArrival case final last?) {
      _intervals.add((arrivalMicros - last) / 1000);
    }
    _firstArrival ??= arrivalMicros;
    _lastArrival = arrivalMicros;
  }

  /// Values per second between the first and the last arrival.
  double get deliveredRateHz {
    final first = _firstArrival;
    final last = _lastArrival;
    if (first == null || last == null || last == first) return 0;
    return (sequence.received - 1) / ((last - first) / 1e6);
  }

  SampleSummary get intervals => SampleSummary.of(_intervals);

  List<Check> checks() => [
    Check(
      'Ran for ${duration.inSeconds} s',
      passed: completed && linkError == null,
      detail: linkError ?? (completed ? 'completed' : 'stopped early'),
    ),
    Check(
      'No lost values',
      passed: sequence.received > 0 && sequence.lost == 0,
      detail: '${sequence.lost} lost of ${sequence.highest + 1} sent',
    ),
    Check(
      'No out-of-order, repeated or corrupt values',
      passed:
          sequence.outOfOrder == 0 &&
          sequence.duplicates == 0 &&
          sequence.implausible == 0 &&
          malformed == 0,
      detail:
          '${sequence.outOfOrder} out of order, ${sequence.duplicates} '
          'repeated, ${sequence.implausible + malformed} corrupt',
    ),
    Check(
      'Delivered at least ${(rateHz * minRateRatio).toStringAsFixed(1)} Hz',
      passed: deliveredRateHz >= rateHz * minRateRatio,
      detail: '${deliveredRateHz.toStringAsFixed(1)} Hz',
    ),
  ];

  String get summary =>
      '${sequence.received} values · ${deliveredRateHz.toStringAsFixed(1)} Hz'
      ' · ${sequence.lost} lost · ${sequence.outOfOrder} out of order';

  Map<String, Object?> toJson() => {
    'requestedRateHz': rateHz,
    'deliveredRateHz': _round(deliveredRateHz),
    ...sequence.toJson(),
    'malformed': malformed,
    'intervalMs': intervals.toJson(),
    'delayVariationMs': delay.millis().toJson(),
    'clockDriftPpm': delay.driftPpm == null ? null : _round(delay.driftPpm!),
    'completed': completed,
    'linkError': linkError,
  };

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
