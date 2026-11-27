import 'package:meta/meta.dart';

/// How a distance is measured.
enum DistanceMethod {
  /// Bluetooth 6.0 Channel Sounding: phase and round-trip time, accurate
  /// to tens of centimetres.
  channelSounding,

  /// Estimated from signal strength: metres of error (Android).
  rssi,
}

/// How often measurements arrive. Android maps it to its update rates;
/// iOS chooses its own.
enum MeasurementRate { low, normal, high }

enum MeasurementConfidence { low, medium, high }

/// One distance measurement to a peripheral.
@immutable
final class DistanceMeasurement {
  const DistanceMeasurement({
    required this.meters,
    required this.method,
    required this.timestamp,
    this.confidence,
    this.standardDeviation,
    this.azimuth,
    this.elevation,
    this.rssi,
  });

  final double meters;
  final DistanceMethod method;
  final DateTime timestamp;

  /// Android only.
  final MeasurementConfidence? confidence;

  /// The standard deviation of [meters], when the platform reports it.
  final double? standardDeviation;

  /// Horizontal angle of arrival in degrees, when the hardware measures it.
  final double? azimuth;

  /// Vertical angle of arrival in degrees, when the hardware measures it.
  final double? elevation;

  final int? rssi;

  @override
  String toString() =>
      'DistanceMeasurement(${meters.toStringAsFixed(2)} m, ${method.name})';
}
