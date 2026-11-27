import 'dart:collection';

enum Trend { warmer, colder, steady }

/// Compares the smoothed signal now with what it was [span] ago.
final class TrendTracker {
  TrendTracker({this.span = const Duration(seconds: 2), this.threshold = 2});

  final Duration span;

  /// The change in dB that counts as warmer or colder.
  final double threshold;

  final _samples = ListQueue<({DateTime at, double rssi})>();

  /// Keeps one sample at least [span] old as the reference, and every newer
  /// one.
  void add(DateTime at, double rssi) {
    _samples.addLast((at: at, rssi: rssi));
    final cutoff = at.subtract(span);
    while (_samples.length > 1 && !_samples.elementAt(1).at.isAfter(cutoff)) {
      _samples.removeFirst();
    }
  }

  Trend trendAt(DateTime now) {
    if (_samples.isEmpty) return Trend.steady;
    final reference = _samples.first;
    if (now.difference(reference.at) < span) return Trend.steady;
    final change = _samples.last.rssi - reference.rssi;
    if (change >= threshold) return Trend.warmer;
    if (change <= -threshold) return Trend.colder;
    return Trend.steady;
  }

  void clear() => _samples.clear();
}
