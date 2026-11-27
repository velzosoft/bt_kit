import 'package:bt_kit/bt_kit.dart';

import '../model/lab_failure.dart';
import '../profile/reference_profile.dart';

/// The reference profile's characteristics on a discovered peripheral.
final class ReferenceCharacteristics {
  ReferenceCharacteristics._(this._found);

  /// Throws [ProfileMismatch] when a characteristic is missing or lacks a
  /// property the profile needs.
  factory ReferenceCharacteristics.of(Peripheral peripheral) {
    final found = <ReferenceCharacteristic, GattCharacteristic>{};
    final problems = <String>[];
    for (final expected in ReferenceCharacteristic.values) {
      final characteristic = peripheral.characteristic(
        ReferenceProfile.service,
        expected.uuid,
      );
      final required = expected.properties.bits;
      if (characteristic == null) {
        problems.add('no ${expected.label}');
      } else if (characteristic.properties.bits & required != required) {
        problems.add('${expected.label} lacks properties');
      } else {
        found[expected] = characteristic;
      }
    }
    if (problems.isNotEmpty) throw ProfileMismatch(problems);
    return ReferenceCharacteristics._(found);
  }

  final Map<ReferenceCharacteristic, GattCharacteristic> _found;

  GattCharacteristic operator [](ReferenceCharacteristic characteristic) =>
      _found[characteristic]!;
}
