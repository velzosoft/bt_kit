import 'package:bt_kit/bt_kit.dart';

/// The value of the database control characteristic: whether the
/// reference serves its extra service. Writing `01` adds it and `00`
/// removes it, which changes the GATT database while centrals are
/// connected.
abstract final class DatabaseCommand {
  static List<int> encode({required bool extraService}) => [
    if (extraService) 0x01 else 0x00,
  ];

  /// Whether to serve the extra service. Throws the [GattException] the
  /// reference answers an invalid write with.
  static bool decode(List<int> bytes) {
    if (bytes.length != 1) {
      throw GattException(GattError.invalidAttributeValueLength, 'database');
    }
    return switch (bytes[0]) {
      0x00 => false,
      0x01 => true,
      _ => throw GattException(GattError.valueNotAllowed, 'database'),
    };
  }
}
