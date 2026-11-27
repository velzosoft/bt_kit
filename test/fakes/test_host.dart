import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/central/device_host.dart';

import 'capabilities.dart' as fakes;

/// A host whose capabilities and permissions tests set directly.
final class TestHost implements DeviceHost {
  @override
  BluetoothCapabilities capabilities = fakes.capabilities();

  final denied = <BluetoothPermission>{};
  final events = <PeripheralEvent>[];
  var settingsOpened = 0;

  @override
  Future<void> ensureReady(Set<BluetoothPermission> permissions) async {
    final missing = permissions.intersection(denied);
    if (missing.isNotEmpty) {
      throw BluetoothPermissionException({
        for (final permission in missing) permission: PermissionStatus.denied,
      }, 'denied');
    }
  }

  @override
  void report(PeripheralEvent event) => events.add(event);

  @override
  Future<void> openBluetoothSettings() async => settingsOpened++;
}
