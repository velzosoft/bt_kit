import 'dart:collection';

/// Smooths RSSI readings: a median of the last [window] readings removes
/// spikes, then an exponential moving average with factor [alpha] removes
/// jitter.
final class RssiFilter {
  RssiFilter({this.window = 5, this.alpha = 0.3})
    : assert(window > 0),
      assert(alpha > 0 && alpha <= 1);

  /// iOS reports this when the signal strength is unavailable.
  static const unavailable = 127;

  final int window;
  final double alpha;
  final _recent = ListQueue<int>();
  double? _value;

  /// The smoothed value in dBm, or null before the first reading.
  double? get value => _value;

  /// Adds a reading and returns the new smoothed value. Unavailable
  /// readings are ignored.
  double? add(int rssi) {
    if (rssi == unavailable) return _value;
    _recent.addLast(rssi);
    if (_recent.length > window) _recent.removeFirst();
    final median = _median();
    final previous = _value;
    return _value = previous == null
        ? median
        : previous + alpha * (median - previous);
  }

  void reset() {
    _recent.clear();
    _value = null;
  }

  double _median() {
    final sorted = _recent.toList()..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle].toDouble()
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
