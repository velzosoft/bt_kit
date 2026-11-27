import '../models/capabilities.dart';
import '../models/permission.dart';
import 'peripheral_event.dart';

/// What remote device objects need from `BtKit`.
abstract interface class DeviceHost {
  BluetoothCapabilities get capabilities;

  /// Checks [permissions] and the adapter; throws when either is missing.
  Future<void> ensureReady(Set<BluetoothPermission> permissions);

  void report(PeripheralEvent event);

  /// Shows the system Bluetooth settings; completes when the user returns.
  Future<void> openBluetoothSettings();
}
