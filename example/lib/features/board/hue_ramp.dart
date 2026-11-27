import 'package:flutter/painting.dart';

/// The colors a held button runs through, shared with the board so its LED
/// and the circle on the screen match.
///
/// The hue starts at green and loses 42° a second, through yellow, orange
/// and red to violet at [duration], where it stays.
abstract final class HueRamp {
  static const duration = Duration(seconds: 5);
  static const startHue = 120.0;
  static const degreesPerSecond = 42.0;

  /// How far along the ramp a hold of [held] is, from 0 to 1.
  static double progress(Duration held) =>
      (held.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);

  /// The hue in degrees after a hold of [held].
  static double hue(Duration held) {
    final seconds = progress(held) * duration.inMicroseconds / 1e6;
    return (startHue - degreesPerSecond * seconds) % 360;
  }

  static Color color(Duration held) =>
      HSVColor.fromAHSV(1, hue(held), 1, 1).toColor();
}
