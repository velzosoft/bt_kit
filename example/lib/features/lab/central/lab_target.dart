import 'package:bt_kit/bt_kit.dart';

import 'reference_locator.dart';

/// The reference peripheral under test.
///
/// Phones in the peripheral role advertise from a random address that
/// changes about every 15 minutes, and an unbonded central then sees a new
/// peripheral. [relocate] finds the reference again by its service.
final class LabTarget {
  LabTarget(this.peripheral);

  Peripheral peripheral;
  var addressChanges = 0;

  /// Whether a reference with a different id was found and is now the
  /// target.
  Future<bool> relocate() async {
    try {
      final found = await ReferenceLocator.find(
        timeout: const Duration(seconds: 10),
      );
      if (found == null || found.id == peripheral.id) return false;
      peripheral = found;
      addressChanges++;
      return true;
    } on BluetoothException {
      return false;
    }
  }
}
