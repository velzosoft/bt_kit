import 'dart:math';

enum HapticWeight { selection, light, medium, heavy }

/// How the Geiger counter sounds and feels at a signal strength from 0
/// (barely heard) to 1 (touching the target).
abstract final class ClickRate {
  static const slowest = Duration(seconds: 2);
  static const fastest = Duration(milliseconds: 30);

  /// Vibrations closer together than this blur into one buzz, so faster
  /// clicks skip some of them.
  static const hapticSpacing = Duration(milliseconds: 90);

  /// Exponential, so that every step closer speeds the clicks up by the
  /// same factor.
  static Duration interval(double strength) {
    final ratio = fastest.inMicroseconds / slowest.inMicroseconds;
    final micros = slowest.inMicroseconds * pow(ratio, _clamp(strength));
    return Duration(microseconds: micros.round());
  }

  static double volume(double strength) => 0.5 + 0.5 * _clamp(strength);

  static HapticWeight hapticWeight(double strength) => switch (strength) {
    < 0.3 => HapticWeight.selection,
    < 0.6 => HapticWeight.light,
    < 0.85 => HapticWeight.medium,
    _ => HapticWeight.heavy,
  };

  static bool vibrates({required Duration sinceLastVibration}) =>
      sinceLastVibration >= hapticSpacing;

  static double _clamp(double strength) => strength.clamp(0.0, 1.0);
}
