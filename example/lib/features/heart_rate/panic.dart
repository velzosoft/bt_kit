/// A player's own reference heart rate: the average of their first minute
/// of readings.
final class HeartRateBaseline {
  static const window = Duration(seconds: 60);

  DateTime? _start;
  var _sum = 0;
  var _count = 0;
  double? _value;

  /// The average BPM, or null while still calibrating.
  double? get value => _value;

  bool get isCalibrating => _value == null;

  /// How long until the baseline is known, counted from the first reading.
  Duration remainingAt(DateTime now) {
    final start = _start;
    if (_value != null) return Duration.zero;
    if (start == null) return window;
    final left = window - now.difference(start);
    return left.isNegative ? Duration.zero : left;
  }

  /// Adds a reading; the first reading after the window closes it.
  void add(int bpm, DateTime at) {
    if (_value != null || bpm <= 0) return;
    final start = _start ??= at;
    if (at.difference(start) < window) {
      _sum += bpm;
      _count++;
    } else {
      _value = _sum / _count;
    }
  }
}

enum PanicLevel {
  calm('Calm'),
  uneasy('Uneasy'),
  tense('Tense'),
  panic('Panic!');

  const PanicLevel(this.label);

  final String label;
}

/// How far a heart rate is above the player's own [HeartRateBaseline].
final class Panic {
  Panic(int bpm, double baseline) : rise = (bpm - baseline) / baseline;

  /// The rise at which the meter is full: 50% above baseline.
  static const fullRise = 0.5;

  /// 0.25 means 25% above baseline; negative below it.
  final double rise;

  int get percent => (rise * 100).round();

  /// The meter's fill, from 0 at or below baseline to 1 at [fullRise].
  double get meter => (rise / fullRise).clamp(0.0, 1.0);

  PanicLevel get level => switch (rise) {
    < 0.10 => PanicLevel.calm,
    < 0.25 => PanicLevel.uneasy,
    < 0.40 => PanicLevel.tense,
    _ => PanicLevel.panic,
  };
}
