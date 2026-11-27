# Layer 1: inventory, coverage and exposure rules

Layer 1 exposes the platform Bluetooth APIs as they are. The generators decide what goes in by rule, and every decision is listed in the generated inventories:

- [inventory/android.md](inventory/android.md): every class in scope, its API level, exposure and member counts, the callback classes, and every omitted member with its reason.
- [inventory/ios.md](inventory/ios.md): every declaration in scope, the iOS version that introduced it, and every omission.

## Sources

| | Android | iOS |
|---|---|---|
| SDK | Android 17, `platforms/android-37.0` (stub sources and `api-versions.xml`) | iOS SDK from the installed Xcode (26 or later) |
| Minimum OS | API 33 | iOS 18.0 |
| Generator | JNIgen 1.1 (`tool/android`) | FFIgen 23 (`tool/ios`) |
| Packages / frameworks | `android.bluetooth`, `android.bluetooth.le`, `android.companion`, `android.ranging.*` | CoreBluetooth, AccessorySetupKit, ExternalAccessory |
| Support types | `Context`, `Intent`, `IntentFilter`, `BroadcastReceiver`, `PackageManager`, `PackageInfo`, `Build`, `Handler`, `Looper`, `ParcelUuid`, `PendingIntent`, `OutcomeReceiver`, `SparseArray`, `UUID`, `Executor`, `Consumer`, `InputStream`, `OutputStream` | `NSUUID`, `NSRunLoopCommonModes`, `NSNotificationCenter`, `NSNotification` (ExternalAccessory connection events), `UIImage` (AccessorySetupKit picker items), plus Foundation types from `package:objective_c` |

API 37.2 is still in beta, so the SDK level is a single constant (`sdkPlatform` in `tool/android/generate_android.dart`). Moving to a new SDK means changing that constant and regenerating.

## Exposure rules

### Android (`tool/android/exposure_rules.dart`)

| Rule | Effect |
|---|---|
| Scope | Every public class in the Bluetooth packages, plus the support classes. Anything else a signature mentions becomes a type-only stub. |
| Non-Bluetooth technology | UWB and Wi-Fi classes in `android.ranging` (`uwb`, `wifi` packages, `Uwb*`, `Wifi*`, `Rtt*`, `DlTdoa*`) and `WifiDeviceFilter` stay types only. |
| Deprecated at or before API 33 | A class or member deprecated at or before the minimum API in `api-versions.xml` is omitted. Overloads are matched by name and arity, and a member is dropped only if every matching overload is deprecated, so a non-deprecated overload is never lost. |
| Callback classes | Abstract, publicly constructible classes with overridable `void onX(...)` methods (`BluetoothGattCallback`, `ScanCallback`, `BroadcastReceiver`, `CompanionDeviceService` ...). Their `onX` methods are omitted because apps implement them, not call them. A generated `implement` factory takes optional handlers instead. Their other methods stay. |
| System-created values | Constructors of final classes named `*Result`, `*Status` or `*Event` are omitted (`ScanResult`, `BondStatus`, `EncryptionStatus`, `DevicePresenceEvent`, codec status types). |
| Implicit constructors | Stub sources imply a default constructor for classes that declare none. It is omitted unless `api-versions.xml` lists it, so Layer 1 never offers a constructor that fails at runtime. |
| `dart:core` collisions | Stubs named `Comparable`, `Duration`, `Exception`, `Pattern` and `Uri` are not exported, so importing Layer 1 never changes what `Duration` means. |
| Interop plumbing | The adapters, their listener interfaces, `ActivityBridge` and `BackgroundDelivery` are generated but hidden from `android.dart`. |

Hidden and `@SystemApi` APIs are not in the public SDK stubs, so they never enter scope.

Current totals: 202 classes in scope, 174 exposed in full, 28 type-only. Omitted members: 108 deprecated, 58 callbacks implemented through handlers, 8 system-created constructors, and 96 implicit constructors.

### iOS (`tool/ios/exposure_rules.dart`)

| Rule | Effect |
|---|---|
| Scope | Declarations prefixed `CB`, `AS` or `EA` from the three frameworks, plus the support types above. Referenced types from other frameworks become stubs. |
| Categories | A category belongs to the class it extends, whatever its own name: UIKit's `NSTextAttachment (UIImage)` is not part of `UIImage`. |
| Name collisions | Names that `dart:core` or `package:objective_c` already export, such as the `NSItemProvider` category of `UIImage`, are not exported. |
| Non-Bluetooth technology | `*WiFi*` declarations (`EAWiFiUnconfiguredAccessory*`, Wi-Fi Aware types of AccessorySetupKit) stay types only. |
| Deprecated at or before iOS 18 | FFIgen's `externalVersions` omits them. APIs introduced after iOS 18 check the running version and throw `OsVersionError`. |
| Delegates | Each protocol gets one `implement` factory with listener semantics. The `$Builder` classes and the extensions that invoke delegate methods are hidden. |
| System-created objects | Classes without any available initializer (`CBPeripheral`, `CBCentral`, `CBATTRequest`, `ASAccessoryEvent` ...) lose `alloc`, `allocWithZone:` and `new`. |

## Coverage matrix

The Layer 2 column shows what the unified API wraps. *L1 only* means the capability is reached through Layer 1.

| Capability | Android | iOS | Layer 2 |
|---|---|---|---|
| Adapter state and changes | `BluetoothAdapter`, `ACTION_STATE_CHANGED` | `CBManager.state` | ✓ |
| Runtime permissions | `BLUETOOTH_SCAN/CONNECT/ADVERTISE` | `CBManager.authorization` | ✓ |
| Ask the user to enable Bluetooth | `ACTION_REQUEST_ENABLE` | — | ✓ (Android) |
| BLE scanning with filters | `BluetoothLeScanner` | `scanForPeripherals` (service filter only) | ✓ |
| Extended / Coded PHY scanning | `ScanSettings.setLegacy/setPhy` | automatic | ✓ |
| Background and offloaded scanning | `PendingIntent` scans, batching | service-filtered, state restoration | ✓ (`PendingIntent` scans, restoration) |
| GATT client: discovery, read, write, notify, indicate | `BluetoothGatt` | `CBPeripheral` | ✓ |
| Descriptors | ✓ | ✓ (CCCD is managed by the system) | ✓ |
| MTU | `requestMtu` | automatic, `maximumWriteValueLength` | ✓ |
| RSSI | `readRemoteRssi` | `readRSSI` | ✓ |
| Connection priority, PHY preference | ✓ | — | ✓ (Android) |
| Reliable writes | `beginReliableWrite` | — | L1 only |
| Bonding and pairing | `createBond`, `BondStatus`, pairing broadcasts | implicit on encryption | ✓ (Android) |
| Removing a bond | `CompanionDeviceManager.removeBond` (API 36) | — | ✓ (Android 16; settings elsewhere) |
| Cross-transport bonding | `createBond(transport)` | `EnableTransportBridgingKey`, `bluetoothTransportBridgingIdentifier` | L1 only |
| GATT server | `BluetoothGattServer` | `CBPeripheralManager` | ✓ |
| Advertising | `BluetoothLeAdvertiser`, `AdvertisingSet` (extended, periodic) | `startAdvertising` (name and service UUIDs) | ✓ |
| L2CAP connection-oriented channels | `createL2capChannel`, `listenUsingL2capChannel` | `openL2CAPChannel`, `publishL2CAPChannel` | ✓ |
| Classic discovery | `startDiscovery`, `ACTION_FOUND` | — | ✓ |
| Classic RFCOMM sockets | `BluetoothSocket`, `BluetoothServerSocket` | — | ✓ |
| MFi accessories over Classic or iAP2 | — | ExternalAccessory (`EASession` streams) | ✓ |
| Audio profile state | A2DP, Headset, Hearing Aid, LE Audio (profile proxies and broadcasts) | system-managed | ✓ (Android, read-only) |
| Other Classic profiles | HID Device, CSIP, codec control | system-managed | L1 only |
| Connection events for other apps' links | `ACTION_ACL_CONNECTED/DISCONNECTED` | `registerForConnectionEvents` | ✓ |
| Companion association and presence | `CompanionDeviceManager`, `CompanionDeviceService` | AccessorySetupKit | ✓ (presence: Android) |
| State restoration and the power alert | — | `CBCentralManagerOptionRestoreIdentifierKey`, `ShowPowerAlertKey` | ✓ |
| Channel Sounding and ranging | `android.ranging` (BLE CS, RSSI), API 36+ | `startChannelSoundingSession`, iOS 27+ | ✓ |
| ANCS authorization | — | `didUpdateANCSAuthorization` | L1 only |

## Not available to apps

These are platform limits, not omissions.

- **Android.** Anything `@SystemApi` or hidden: periodic advertising sync, `BluetoothDevice.removeBond` (`CompanionDeviceManager.removeBond` replaces it on API 36), setting the scan mode or discoverable timeout without the user dialog, `BluetoothAdapter.enable()` (deprecated in API 33 and a no-op for apps).
- **iOS.** Bluetooth Classic outside MFi, MAC addresses (peripherals have a per-app UUID), MTU requests, PHY selection, connection parameters, raw advertisement bytes, advertising anything but a local name and service UUIDs, and scanning or advertising arbitrary data in the background.
