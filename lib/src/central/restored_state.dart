import '../core/bluetooth_uuid.dart';
import 'peripheral.dart';

/// What iOS restored after relaunching the app for a Bluetooth event
/// (state restoration); see `BtKitOptions.restoreIdentifier`.
sealed class RestoredState {
  const RestoredState();
}

/// The central role's connections and scan.
final class RestoredCentral extends RestoredState {
  const RestoredCentral(this.peripherals, this.scanServices);

  /// Peripherals connected or connecting when the app was terminated, with
  /// their current connection state. Discover their services again.
  final List<Peripheral> peripherals;

  /// The services the app was scanning for; scan for them again to keep
  /// receiving results.
  final List<BluetoothUuid> scanServices;

  @override
  String toString() =>
      'RestoredCentral(${peripherals.length} peripherals, '
      'scanning for ${scanServices.length} services)';
}

/// The peripheral role's services and advertisement.
///
/// The services stay published. Open the `GattServer` with the same
/// `LocalService`s to serve them again: services with a restored UUID are
/// adopted instead of being added twice.
final class RestoredPeripheralRole extends RestoredState {
  const RestoredPeripheralRole(this.services, {required this.advertising});

  final List<BluetoothUuid> services;

  /// Whether the advertisement is still running. Start advertising again
  /// to get an `AdvertisingSession` for it.
  final bool advertising;

  @override
  String toString() =>
      'RestoredPeripheralRole(${services.length} services'
      '${advertising ? ', advertising' : ''})';
}
