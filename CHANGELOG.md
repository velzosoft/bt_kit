## 1.0.0

Initial release.

- Layer 2, a unified Dart API for Android and iOS (`package:bt_kit/bt_kit.dart`):
  - Central role: permissions, adapter state, capability queries, shared scanning with advertisement filters, device lists, connections, GATT client, notifications and indications, MTU, PHY, connection priority, Services Changed and disconnect reasons.
  - Peripheral role: a GATT server with local services as plain data, long reads, prepared writes and per-central notification queues; advertising, including extended and periodic advertising on Android.
  - Byte channels: L2CAP on both platforms, Bluetooth Classic discovery and RFCOMM sockets on Android, and MFi accessory sessions on iOS, all through `ByteChannel`.
  - Bonding, the companion device picker (CompanionDeviceManager and AccessorySetupKit), background scans and companion presence on Android, and state restoration on iOS.
  - Distance through Channel Sounding and RSSI ranging, and audio profile state on Android.
  - A per-peripheral operation queue, a timeout and a `CancelToken` on every operation, and a sealed exception hierarchy.
  - Logging under `bt_kit.*`, gated by `BtKit.logLevel`.
- Layer 1: every public Android Bluetooth API through JNIgen (`package:bt_kit/android.dart`), and CoreBluetooth, AccessorySetupKit and ExternalAccessory through FFIgen (`package:bt_kit/ios.dart`).
- `package:bt_kit/testing.dart`: `FakeBluetooth` and `FakePeripheral` for app tests that run without a radio.
- Example app, Bluetooth Radar, with an on-device test suite and ESP32 reference firmware.
