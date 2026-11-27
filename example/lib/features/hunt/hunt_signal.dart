import '../../bluetooth/rssi_filter.dart';
import '../../bluetooth/signal.dart';
import 'signal_trend.dart';

enum HuntStatus {
  /// Listening, and nothing heard yet.
  searching,
  live,

  /// Nothing heard for [HuntSignal.lostAfter].
  lost,
}

final class HuntReading {
  const HuntReading({
    required this.status,
    this.rssi,
    this.trend = Trend.steady,
    this.silence,
  });

  const HuntReading.searching() : this(status: HuntStatus.searching);

  final HuntStatus status;

  /// Smoothed signal strength in dBm.
  final double? rssi;
  final Trend trend;

  /// How long since the target was last heard, or null if it never was.
  final Duration? silence;

  bool get isLive => status == HuntStatus.live;

  /// From 0 (barely heard) to 1 (touching); 0 unless [isLive].
  double get strength => isLive ? Signal.strength(rssi!) : 0;
}

/// One target's signal: smoothed, with its trend, and lost after
/// [lostAfter] without an advertisement.
final class HuntSignal {
  HuntSignal(DateTime start) : _since = start;

  static const lostAfter = Duration(seconds: 5);

  final _filter = RssiFilter();
  final _trend = TrendTracker();
  DateTime _since;
  DateTime? _lastHeard;

  void add(int rssi, DateTime at) {
    final smoothed = _filter.add(rssi);
    if (smoothed == null) return;
    _lastHeard = at;
    _trend.add(at, smoothed);
  }

  /// Forgets every reading, as when listening resumes after a pause: old
  /// readings say nothing about where the target is now.
  void restart(DateTime at) {
    _filter.reset();
    _trend.clear();
    _since = at;
    _lastHeard = null;
  }

  HuntReading readingAt(DateTime now) {
    final lastHeard = _lastHeard;
    final silence = lastHeard == null ? null : now.difference(lastHeard);
    if (now.difference(lastHeard ?? _since) > lostAfter) {
      return HuntReading(status: HuntStatus.lost, silence: silence);
    }
    if (lastHeard == null) return const HuntReading.searching();
    return HuntReading(
      status: HuntStatus.live,
      rssi: _filter.value,
      trend: _trend.trendAt(now),
      silence: silence,
    );
  }
}
