import 'package:meta/meta.dart';

/// Options fixed when bt_kit first creates its platform managers; set them
/// with `BtKit.configure` before anything else uses bt_kit.
///
/// They concern iOS, where `CBCentralManager` and `CBPeripheralManager`
/// take them at creation. Android ignores them.
@immutable
final class BtKitOptions {
  const BtKitOptions({
    this.showPowerAlert = false,
    this.restoreIdentifier,
    this.peripheralRestoreIdentifier,
  });

  /// Whether iOS asks the user to turn Bluetooth on when bt_kit needs it
  /// and it is off.
  final bool showPowerAlert;

  /// Opts the central role into state restoration: iOS relaunches the app
  /// in the background for its connections and scans, and `BtKit.restored`
  /// reports what it restored. Needs the `bluetooth-central` background
  /// mode.
  final String? restoreIdentifier;

  /// The same for the peripheral role: its services and advertisement
  /// survive while the app is not running. Needs the `bluetooth-peripheral`
  /// background mode.
  final String? peripheralRestoreIdentifier;
}
