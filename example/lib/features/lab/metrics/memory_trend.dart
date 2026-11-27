/// Process memory sampled against the number of scan results, to tell a
/// leak, which grows with the results, from garbage-collector noise.
final class MemoryTrend {
  MemoryTrend({required this.warmup});

  /// Results received before the measurement starts, while caches, JIT and
  /// the scan pipeline settle.
  final int warmup;
  final _samples = <({int results, int bytes})>[];

  List<({int results, int bytes})> get samples => List.unmodifiable(_samples);

  void add({required int results, required int bytes}) =>
      _samples.add((results: results, bytes: bytes));

  List<({int results, int bytes})> get _measured => [
    for (final s in _samples)
      if (s.results >= warmup) s,
  ];

  /// The median of the last quarter of the measured samples minus the
  /// median of the first quarter; null with fewer than four samples.
  int? get growthBytes {
    final measured = _measured;
    if (measured.length < 4) return null;
    final quarter = measured.length ~/ 4;
    return _median(measured.skip(measured.length - quarter)) -
        _median(measured.take(quarter));
  }

  /// The least-squares slope of memory over results after warm-up.
  double? get bytesPerResult {
    final measured = _measured;
    if (measured.length < 2) return null;
    final meanX = measured.fold(0.0, (a, s) => a + s.results) / measured.length;
    final meanY = measured.fold(0.0, (a, s) => a + s.bytes) / measured.length;
    var covariance = 0.0;
    var variance = 0.0;
    for (final s in measured) {
      covariance += (s.results - meanX) * (s.bytes - meanY);
      variance += (s.results - meanX) * (s.results - meanX);
    }
    return variance == 0 ? null : covariance / variance;
  }

  static int _median(Iterable<({int results, int bytes})> samples) {
    final sorted = [for (final s in samples) s.bytes]..sort();
    return sorted[sorted.length ~/ 2];
  }
}
