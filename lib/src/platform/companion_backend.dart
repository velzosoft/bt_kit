import '../central/native_types.dart';
import '../models/companion_request.dart';

export '../models/companion_request.dart' show CompanionChangeKind;

/// The system companion device picker and its associations:
/// `CompanionDeviceManager` on Android, AccessorySetupKit on iOS.
abstract interface class CompanionBackend {
  /// Shows the picker and returns the device the user chose, or null when
  /// they dismissed it.
  Future<CompanionDeviceBackend?> associate(CompanionRequest request);

  Future<List<CompanionDeviceBackend>> devices();

  Future<void> remove(CompanionDeviceBackend device);

  /// Devices added, removed or changed outside [associate] and [remove]
  /// (iOS); reported while listened.
  Stream<CompanionChange> get changes;

  /// Starts or stops presence events for [device] (Android).
  Future<void> observePresence(
    CompanionDeviceBackend device, {
    required bool observe,
  });
}

abstract interface class CompanionDeviceBackend {
  String get id;
  String? get name;

  /// The id `BtKit.peripheral` takes, when the device has one.
  String? get peripheralId;
  CompanionHandle get native;
}

typedef CompanionChange = ({
  CompanionDeviceBackend device,
  CompanionChangeKind kind,
});
