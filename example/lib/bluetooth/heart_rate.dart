import 'package:bt_kit/bt_kit.dart';

/// The standard Heart Rate and Battery services a strap exposes.
abstract final class HeartRateUuids {
  static final service = BluetoothUuid.short(0x180d);
  static final measurement = BluetoothUuid.short(0x2a37);
  static final batteryService = BluetoothUuid.short(0x180f);
  static final batteryLevel = BluetoothUuid.short(0x2a19);
}

/// Sensor Contact Status, from flags bits 1–2.
enum SensorContact {
  /// The sensor cannot tell whether it touches the skin.
  unsupported,

  /// The sensor can tell, and it does not: the strap needs adjusting.
  notDetected,

  detected,
}

/// One Heart Rate Measurement (`2A37`) value.
final class HeartRateMeasurement {
  const HeartRateMeasurement({
    required this.bpm,
    this.contact = SensorContact.unsupported,
    this.energyExpended,
    this.rrIntervals = const [],
  });

  /// Parses a notification value. Returns null when it is too short to hold
  /// a heart rate; truncated optional fields are left out.
  static HeartRateMeasurement? parse(List<int> value) {
    if (value.isEmpty) return null;
    final flags = value[0];
    final reader = _LittleEndianReader(value, 1);
    final bpm = flags & 0x01 == 0 ? reader.uint8() : reader.uint16();
    if (bpm == null) return null;
    final energyExpended = flags & 0x08 == 0 ? null : reader.uint16();
    return HeartRateMeasurement(
      bpm: bpm,
      contact: _contact(flags),
      energyExpended: energyExpended,
      rrIntervals: [
        if (flags & 0x10 != 0)
          for (var rr = reader.uint16(); rr != null; rr = reader.uint16())
            Duration(microseconds: (rr * 1000000 / 1024).round()),
      ],
    );
  }

  final int bpm;
  final SensorContact contact;

  /// Kilojoules since the sensor last reset its counter.
  final int? energyExpended;

  /// Times between consecutive beats, oldest first.
  final List<Duration> rrIntervals;

  static SensorContact _contact(int flags) => switch ((flags >> 1) & 0x03) {
    2 => SensorContact.notDetected,
    3 => SensorContact.detected,
    _ => SensorContact.unsupported,
  };
}

final class _LittleEndianReader {
  _LittleEndianReader(this._bytes, this._offset);

  final List<int> _bytes;
  int _offset;

  int? uint8() {
    if (_offset + 1 > _bytes.length) return null;
    return _bytes[_offset++];
  }

  int? uint16() {
    if (_offset + 2 > _bytes.length) return null;
    final value = _bytes[_offset] | _bytes[_offset + 1] << 8;
    _offset += 2;
    return value;
  }
}
