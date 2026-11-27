/// Relative closeness from signal strength. RSSI cannot give meters, so the
/// app only ever says near, around or far.
enum Proximity {
  near('Near'),
  around('Around'),
  far('Far');

  const Proximity(this.label);

  final String label;
}

/// Maps smoothed RSSI to the app's honest, unitless scales.
abstract final class Signal {
  static const strongest = -35.0;
  static const weakest = -100.0;
  static const nearAbove = -60.0;
  static const farBelow = -80.0;

  static Proximity proximity(double rssi) => switch (rssi) {
    >= nearAbove => Proximity.near,
    >= farBelow => Proximity.around,
    _ => Proximity.far,
  };

  /// 0 for the weakest detectable signal, 1 when touching the device.
  static double strength(double rssi) =>
      ((rssi - weakest) / (strongest - weakest)).clamp(0.0, 1.0);

  /// Distance from the radar center, from 0 (center) to 1 (edge).
  static double radius(double rssi) => 0.1 + 0.88 * (1 - strength(rssi));

  /// A stable angle in radians for [id]. Bluetooth gives no direction, so
  /// the angle only keeps each device in the same place.
  static double angle(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash / 0x100000000 * 2 * 3.141592653589793;
  }
}
