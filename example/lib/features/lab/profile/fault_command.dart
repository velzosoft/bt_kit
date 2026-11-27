import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

/// The value of the fault control characteristic: one byte holding the ATT
/// error code that reads of the fault target fail with, or `00` for none.
abstract final class FaultCommand {
  static Uint8List encode(GattError? fault) =>
      Uint8List.fromList([fault?.code ?? 0]);

  /// The fault to serve, or null to clear it. Throws the [GattException]
  /// the reference answers an invalid write with.
  static GattError? decode(List<int> bytes) {
    if (bytes.length != 1) {
      throw GattException(GattError.invalidAttributeValueLength, 'fault');
    }
    if (bytes[0] == 0) return null;
    final fault = GattError.fromCode(bytes[0]);
    if (fault == GattError.unknown) {
      throw GattException(GattError.valueNotAllowed, 'fault');
    }
    return fault;
  }
}
