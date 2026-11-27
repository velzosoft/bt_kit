import 'package:meta/meta.dart';

/// A Bluetooth UUID.
///
/// Short 16- and 32-bit assigned numbers are expanded onto the Bluetooth
/// base UUID, so `BluetoothUuid.parse('180d')` equals
/// `BluetoothUuid.parse('0000180d-0000-1000-8000-00805f9b34fb')`.
@immutable
final class BluetoothUuid {
  const BluetoothUuid._(this.value);

  /// Parses a 4, 8 or 32 hex-digit UUID, with or without dashes.
  factory BluetoothUuid.parse(String uuid) {
    final hex = uuid.replaceAll('-', '').toLowerCase();
    if (!_hex.hasMatch(hex)) {
      throw FormatException('Invalid Bluetooth UUID', uuid);
    }
    return switch (hex.length) {
      4 || 8 => BluetoothUuid._('${hex.padLeft(8, '0')}$_baseSuffix'),
      32 => BluetoothUuid._(
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}',
      ),
      _ => throw FormatException('Invalid Bluetooth UUID length', uuid),
    };
  }

  /// A 16- or 32-bit assigned number, such as `0x180d` (Heart Rate).
  factory BluetoothUuid.short(int value) {
    RangeError.checkValueInInterval(value, 0, 0xffffffff, 'value');
    return BluetoothUuid._(
      '${value.toRadixString(16).padLeft(8, '0')}$_baseSuffix',
    );
  }

  /// A UUID in the little-endian byte order used over the air: 2, 4 or 16
  /// bytes.
  factory BluetoothUuid.fromBytes(List<int> bytes) {
    final hex = bytes.reversed
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return switch (bytes.length) {
      2 || 4 || 16 => BluetoothUuid.parse(hex),
      _ => throw FormatException('Invalid Bluetooth UUID byte length', bytes),
    };
  }

  /// The Client Characteristic Configuration descriptor.
  static final clientCharacteristicConfiguration = BluetoothUuid.short(0x2902);

  /// The Serial Port Profile service class, for RFCOMM serial devices.
  static final serialPort = BluetoothUuid.short(0x1101);

  static const _baseSuffix = '-0000-1000-8000-00805f9b34fb';
  static final _hex = RegExp(r'^[0-9a-f]+$');

  /// The full lowercase 128-bit form.
  final String value;

  /// The assigned number, if this UUID derives from the base UUID.
  int? get shortValue => value.endsWith(_baseSuffix)
      ? int.parse(value.substring(0, 8), radix: 16)
      : null;

  @override
  bool operator ==(Object other) =>
      other is BluetoothUuid && other.value == value;

  @override
  int get hashCode => value.hashCode;

  /// The shortest standard form: `180d`, `0001fffe` or the full UUID.
  @override
  String toString() => switch (shortValue) {
    final short? when short <= 0xffff =>
      short.toRadixString(16).padLeft(4, '0'),
    final short? => short.toRadixString(16).padLeft(8, '0'),
    null => value,
  };
}
