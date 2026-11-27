import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/app_uuids.dart';
import 'package:bt_radar/features/lab/central/reference_locator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A service UUID no reference peripheral uses, for what the smoke test
/// creates itself.
final smokeService = AppUuids.labUuid(0x1ff);

/// Delegates and callbacks that the platform holds weakly, kept alive for
/// the whole run.
final keepAlive = <Object>[];

/// Waits for [future], failing with a readable message after [timeout].
Future<T> waitFor<T>(
  Future<T> future,
  String what, {
  Duration timeout = const Duration(seconds: 10),
}) => future.timeout(
  timeout,
  onTimeout: () => throw TestFailure('No $what within ${timeout.inSeconds} s'),
);

/// Asks for every Bluetooth permission, and checks Bluetooth is on.
///
/// On Android, grant them beforehand to run unattended:
/// `adb shell pm grant dev.btkit.bt_radar android.permission.BLUETOOTH_SCAN`
/// (and `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE`).
Future<void> prepareBluetooth() async {
  final bt = BtKit.instance;
  final statuses = await bt.requestPermissions({
    ...BtKit.centralPermissions,
    ...BtKit.peripheralPermissions,
  });
  final missing = [
    for (final MapEntry(:key, :value) in statuses.entries)
      if (!value.isGranted) '${key.name} (${value.name})',
  ];
  if (missing.isNotEmpty) {
    fail('Bluetooth permissions are not granted: ${missing.join(', ')}');
  }
  var state = bt.adapterState;
  if (!state.isPoweredOn) {
    state = await bt.adapterStateChanges
        .firstWhere((s) => s.isPoweredOn)
        .timeout(const Duration(seconds: 3), onTimeout: () => bt.adapterState);
  }
  if (!state.isPoweredOn) fail('Bluetooth is ${state.name}; turn it on first');
}

/// The Lab reference peripheral, or null after [timeout] with a message
/// explaining how to provide one.
Future<Peripheral?> findReference({
  Duration timeout = const Duration(seconds: 20),
}) async {
  final found = await ReferenceLocator.find(timeout: timeout);
  if (found == null) {
    debugPrint(
      'No Lab reference peripheral advertised within ${timeout.inSeconds} s. '
      'On a second phone, open the Lab (long-press the Radar title) and '
      'start Be the reference, or flash firmware that implements '
      'example/peripheral/README.md. Tests that need it are skipped.',
    );
  }
  return found;
}
