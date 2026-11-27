import 'dart:math' as math;

import 'sample_summary.dart';

/// How much later than the fastest value each value arrived, between two
/// devices whose clocks are not synchronized.
///
/// Arrival time minus the sender's timestamp is the one-way delay plus an
/// unknown clock offset that drifts by a few ppm. A least-squares line
/// through those differences removes offset and drift; what remains,
/// measured from the smallest residual, is the delay variation.
final class DelayVariation {
  final _sent = <int>[];
  final _received = <int>[];

  int get count => _sent.length;

  void add({required int sentMicros, required int receivedMicros}) {
    _sent.add(sentMicros);
    _received.add(receivedMicros);
  }

  /// The fitted drift between the two clocks, in parts per million.
  double? get driftPpm {
    final fit = _fit();
    return fit == null ? null : fit.slope * 1e6;
  }

  /// The variation of every value, in milliseconds.
  SampleSummary millis() {
    final fit = _fit();
    if (fit == null) return SampleSummary.empty;
    final residuals = [
      for (var i = 0; i < count; i++)
        _offset(i) - fit.intercept - fit.slope * _sent[i],
    ];
    final fastest = residuals.reduce(math.min);
    return SampleSummary.of([for (final r in residuals) (r - fastest) / 1000]);
  }

  double _offset(int i) => (_received[i] - _sent[i]).toDouble();

  ({double slope, double intercept})? _fit() {
    if (count < 2) return null;
    final meanX = _sent.fold(0.0, (a, b) => a + b) / count;
    var meanY = 0.0;
    for (var i = 0; i < count; i++) {
      meanY += _offset(i);
    }
    meanY /= count;
    var covariance = 0.0;
    var variance = 0.0;
    for (var i = 0; i < count; i++) {
      final dx = _sent[i] - meanX;
      covariance += dx * (_offset(i) - meanY);
      variance += dx * dx;
    }
    final slope = variance == 0 ? 0.0 : covariance / variance;
    return (slope: slope, intercept: meanY - slope * meanX);
  }
}
