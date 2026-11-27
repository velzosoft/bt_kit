/// Fakes for testing apps that use bt_kit, on the host and without a radio.
///
/// [FakeBluetooth.install] replaces `BtKit.instance` with a simulated stack
/// whose peripherals are [FakePeripheral]s:
///
/// ```dart
/// import 'package:bt_kit/testing.dart';
///
/// late FakeBluetooth bluetooth;
///
/// setUp(() => bluetooth = FakeBluetooth.install());
/// tearDown(FakeBluetooth.uninstall);
/// ```
library;

export 'src/testing/fake_bluetooth.dart';
