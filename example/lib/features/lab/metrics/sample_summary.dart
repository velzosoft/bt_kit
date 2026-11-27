/// Count, mean and nearest-rank percentiles of a set of samples, such as
/// latencies in milliseconds.
final class SampleSummary {
  const SampleSummary._({
    required this.count,
    required this.min,
    required this.mean,
    required this.p50,
    required this.p95,
    required this.p99,
    required this.max,
  });

  factory SampleSummary.of(Iterable<num> samples) {
    final sorted = [for (final s in samples) s.toDouble()]..sort();
    if (sorted.isEmpty) return empty;
    final sum = sorted.fold(0.0, (a, b) => a + b);
    return SampleSummary._(
      count: sorted.length,
      min: sorted.first,
      mean: sum / sorted.length,
      p50: percentile(sorted, 50),
      p95: percentile(sorted, 95),
      p99: percentile(sorted, 99),
      max: sorted.last,
    );
  }

  static const empty = SampleSummary._(
    count: 0,
    min: 0,
    mean: 0,
    p50: 0,
    p95: 0,
    p99: 0,
    max: 0,
  );

  final int count;
  final double min;
  final double mean;
  final double p50;
  final double p95;
  final double p99;
  final double max;

  /// The smallest sample with at least [p] percent of [sorted] at or below
  /// it.
  static double percentile(List<double> sorted, double p) {
    final rank = (p / 100 * sorted.length).ceil().clamp(1, sorted.length);
    return sorted[rank - 1];
  }

  Map<String, Object?> toJson() => count == 0
      ? const {'count': 0}
      : {
          'count': count,
          'min': _round(min),
          'mean': _round(mean),
          'p50': _round(p50),
          'p95': _round(p95),
          'p99': _round(p99),
          'max': _round(max),
        };

  /// Such as "p50 12.3 · p99 40.1 ms".
  String brief(String unit) => count == 0
      ? 'no samples'
      : 'p50 ${_short(p50)} · p99 ${_short(p99)} $unit';

  static double _round(double value) => (value * 100).roundToDouble() / 100;

  static String _short(double value) =>
      value >= 100 ? value.round().toString() : value.toStringAsFixed(1);
}
