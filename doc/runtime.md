# Resources, lifecycle, threading, permissions and security

## Threading

| | Android | iOS |
|---|---|---|
| Dart → platform | JNI calls run synchronously on the calling thread. Flutter runs the root isolate on the platform thread, so Layer 2 calls the framework from the main thread. | Objective-C messages run synchronously on the calling thread, which is the main thread for the same reason. |
| Platform → Dart | Binder and main-thread callbacks reach the Java adapters, which call the Dart listener with `$async: true`: the call is posted to the isolate and Java returns at once. | Delegates are built with listener semantics: the trampoline retains the arguments and posts the call to the isolate. |
| Callback queue | `BluetoothGattCallback` runs on binder threads; scan and broadcast callbacks run on the main thread; ranging sessions report on `Context.getMainExecutor()`. | Layer 2 creates `CBCentralManager` with the main queue and activates `ASAccessorySession` on the main dispatch queue. |

Neither direction ever blocks a platform thread waiting for Dart. JNI handles a synchronous call made on the isolate's own thread directly, so a Layer 1 user who opts out of `$async` still cannot deadlock the merged platform thread. Events reach Dart in the order each platform thread emitted them.

### Byte channels: L2CAP, RFCOMM and accessory sessions

**Android.** `BluetoothSocket` and `BluetoothServerSocket` calls block, for L2CAP and RFCOMM alike, so none of them run on the root isolate (`platform/android/socket_io.dart`):

| Worker isolate | Work |
|---|---|
| Reader, one per channel | Loops on `InputStream.read` and sends data back as `TransferableTypedData` (no copy). |
| Writer, one per channel | Runs `connect()` first, then writes queued chunks in order and acknowledges each. |
| Acceptor, one per server | Loops on `accept()`. |

Workers get the socket as a shared `JObject`, which jni supports across isolates. The root isolate owns the reference and keeps it alive until the channel closes. Accepted sockets come back through a one-slot Java array owned by the root isolate, so each side holds its own reference. Closing the socket from the root isolate ends a blocked `read` or `accept` with an `IOException`, and the workers exit.

**iOS.** A `CBL2CAPChannel` and an `EASession` both expose non-blocking `NSStream`s. `IosStreamChannel` schedules them on the main run loop in the common modes, and a listener `NSStreamDelegate` reports readable data, free space, end and errors to the isolate.

## Resource ownership

| Resource | Owner | Released |
|---|---|---|
| JNI global references | The Dart wrapper | When the wrapper is garbage collected (`NativeFinalizer`). Hot paths release eagerly: scan records, byte arrays, strings, callback arguments. The JNI limit is about 50,000 live references. |
| Objective-C objects | The Dart wrapper (+1 retain) | When the wrapper is garbage collected. |
| Java callback proxies | Java | When Java collects the proxy, JNI closes its Dart port. A `BluetoothGatt` keeps its callback while open. |
| Objective-C delegates | Dart (delegate properties are weak) | Each Layer 2 client owns its delegate for as long as it lives. |
| `BluetoothGatt` | `AndroidGattClient` | `close()` after every disconnection, failed connection or cancelled attempt. Android has a small pool of client slots. |
| Native scans | `ScanSessions` | When the last listener cancels or `ScanOptions.timeout` passes. |
| Broadcast receivers | `AndroidCentral` and its parts | Each is registered on the first listener and unregistered after the last: adapter state, bond changes (while a peripheral is connected, bonding, or the app listens to `bondStates`), discovery, ACL connections and audio profiles. |
| Profile proxies | `AndroidAudio` | Opened for one `connections()` call and closed after it. |
| Ranging sessions | `Peripheral.measureDistance` | Stopped and closed when the listener cancels; one per peripheral. |
| Companion association callbacks | `AndroidCompanion` | Kept until the association succeeds, fails or is dismissed. |
| `ASAccessorySession` | `IosCompanion` | Created and activated on first use, for the life of the app. |
| ExternalAccessory notifications | `IosAccessories` | Observed while `accessories.changes` has listeners. |
| The headless engine | `BackgroundDelivery` | Started for the first background event that no engine listens for; it lives as long as the process. |
| Notification subscriptions | `Peripheral` | Notifications are disabled after the last listener cancels and closed when the link drops. |
| `Peripheral` objects | `BtKit` keeps weak references | One object per device while referenced, so state and queues are never split. |
| `BluetoothGattServer` / `CBPeripheralManager` services | `GattServer` | `close()` removes the services and closes the server. iOS allows one server per app. |
| Per-central state (subscriptions, long-read snapshots, prepared writes, notification queues) | `GattServer` and its backend | When the central disconnects (Android), or when the server closes. |
| Advertising sets | `AdvertisingSession` | `stop()`. If `startAdvertising` times out or is cancelled, a set that starts later is stopped at once. |
| L2CAP and RFCOMM sockets, accessory sessions, streams and worker isolates | The channel or server backend, registered until closed | `close()` on either side. Open channels stay registered even if the app drops them, so workers never use a freed socket. |

A connected peripheral stays alive through its platform callback. Call `disconnect()` when done. A disconnected peripheral that nothing references is released automatically.

## Operation lifecycle

Every one-shot operation goes through `Peripheral`'s `OperationQueue`:

1. **Wait** behind earlier operations. A cancelled waiting operation never reaches the platform.
2. **Start**: exactly one platform request is in flight per connection, tracked by a `RequestSlot`.
3. **Complete** when the matching callback arrives. Callbacks that do not match the pending request (Layer 1 traffic, stale answers) are ignored.
4. **Timeout or cancel**: the caller gets `OperationTimeoutException` or `OperationCancelledException` at once. An operation that already reached the platform keeps the queue until the platform answers, so requests never overlap. Its late answer settles it and is discarded. If the platform never answers, the queue is released 30 s (the ATT transaction timeout) after the operation's timeout; by then both stacks have dropped the link.
5. **Disconnect**: the pending request and all waiting operations fail with `DisconnectedException`, and subscriptions end with the same error.

Default timeouts: connect and opening an L2CAP or RFCOMM channel 30 s, discovery 30 s, other GATT operations 10 s, starting advertising or publishing an L2CAP channel 10 s, channel writes 30 s, and pairing or removing a bond 60 s, since both can wait for the user. A pairing that times out or is cancelled is stopped with `cancelBondProcess`. Every method accepts its own `timeout` and `CancelToken`. User-driven prompts (permissions, enabling Bluetooth, the companion picker) have no timeout; the companion picker takes a `CancelToken`.

On the server side, `ReadHandler`s and `WriteHandler`s get `GattServer.requestTimeout` (10 s), well inside the 30 s ATT transaction timeout. A handler that is late or throws anything other than `GattException` is answered with `unlikelyError`, so a central never waits for a reply that does not come.

## Errors

All failures are subclasses of the sealed `BluetoothException`, so a `switch` over them is exhaustive:

| Exception | Meaning |
|---|---|
| `BluetoothUnavailableException` | Adapter off, resetting, unsupported or unauthorized |
| `BluetoothPermissionException` | Not granted, or not declared by the app |
| `UnsupportedFeatureException` | Not offered by this platform; check `capabilities` first |
| `ScanException` | Scan could not start or failed |
| `ConnectionException` | Connection attempt failed (`nativeCode` carries Android's status, such as 133) |
| `BondException` | Pairing failed or was rejected, or a bond could not be removed |
| `RangingException` | A distance measurement could not start or stopped (`nativeCode` carries the reason) |
| `DisconnectedException` | Not connected, or the link dropped mid-operation |
| `GattException` | The peer answered with an ATT error (`GattError`) |
| `NativeOperationException` | The platform refused to start the request |
| `OperationTimeoutException`, `OperationCancelledException` | Timeout or `CancelToken` |

Java exceptions from JNI (`JThrowable`) and `NSError`s are translated at the backend boundary. `nativeCode` and `nativeError` keep the original.

## Capability queries

`BtKit.capabilities` answers before anything fails: LE, Classic, 2M and Coded PHY, extended and periodic advertising, Channel Sounding and RSSI ranging, MTU requests, connection priority, requesting enable, bonding and bond removal, ExternalAccessory, the companion picker, background events, state restoration, system connection events and audio profile state. Methods that cannot work on a platform throw `UnsupportedFeatureException` with an explanation instead of crashing in native code. In Layer 1, APIs newer than the running OS throw `OsVersionError` on iOS, while on Android they raise a JNI `NoSuchMethodError`. Check `Build$VERSION.SDK_INT` against the *Since* column of the inventory first.

## Permissions

| | Android (API 33+) | iOS |
|---|---|---|
| Declared by the app | `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` and, for distance, `RANGING` in `AndroidManifest.xml`. Add `android:usesPermissionFlags="neverForLocation"` to `BLUETOOTH_SCAN` unless the app derives location from scans. | `NSBluetoothAlwaysUsageDescription` in `Info.plist`, or `NSAccessorySetupKitSupports` for apps that reach their devices only through AccessorySetupKit |
| Granted at runtime | Each permission separately | One authorization for everything |
| Check | `checkSelfPermission`, plus the manifest via `PackageManager` | `CBManager.authorization`, plus `Info.plist` via `NSBundle` |
| Request | `Activity.requestPermissions` through `ActivityBridge` | Creating `CBCentralManager` shows the prompt |
| Permanent denial | Denied and `shouldShowRequestPermissionRationale` is false after a request | `denied` |

The package declares no permissions itself. A missing declaration is reported as `PermissionStatus.notDeclared` instead of crashing. Layer 2 never prompts implicitly: `scan()`, `classic.discover()` and `startBackgroundScan()` need `scan`; `connect()`, bonding, RFCOMM, `systemConnections()` and `audio` need `connect`; `openGattServer()` and `publishL2capChannel()` need `connect`; `startAdvertising()` needs `advertise`; `measureDistance()` needs `connect` and `ranging`. The companion picker and ExternalAccessory need no Bluetooth permission. Each throws `BluetoothPermissionException` until `requestPermissions()` succeeds (pass `BtKit.peripheralPermissions` for the peripheral role). On iOS, Layer 2 does not create a `CBCentralManager` or `CBPeripheralManager` until the app asks for permission or is already authorized, so reading `adapterState` never shows a prompt.

## Background execution

| | Android | iOS |
|---|---|---|
| While the app's process runs | Scans and connections continue. Unfiltered scans stop while the screen is off. | Needs `bluetooth-central` / `bluetooth-peripheral` in `UIBackgroundModes`. Scans must filter by service. |
| Process not running | `startBackgroundScan` (a `PendingIntent` scan) and `CompanionDevices.startObservingPresence` start the process. | State restoration (`BtKitOptions.restoreIdentifier`) relaunches the app; `BtKit.restored` reports what iOS kept. |
| Dart while headless | `BackgroundDelivery` sends each event to the engine listening to `BtKit.backgroundEvents`. If none listens, it queues the event (at most 64) and starts a headless engine that runs the handler from `BtKit.registerBackgroundHandler`; the receiver stays alive until the handler acknowledges the event, at most 9 s. Without a handler, events are dropped. | The relaunched app's engine starts normally; `BtKit.configure` must run in `main` so the managers are restored at once. |

## Security

- **No hidden or system APIs.** Layer 1 is generated from public SDK stubs and headers only.
- **Encryption.** Android pairs on demand when a characteristic requires encryption, or explicitly via `createBond`. iOS pairs on demand only, and the system owns the pairing UI.
- **Removing bonds.** bt_kit never calls the hidden `BluetoothDevice.removeBond()`, which needs `BLUETOOTH_PRIVILEGED` once apps target API 37. On API 36+ it uses `CompanionDeviceManager.removeBond`, which needs an association the user confirms.
- **No secrets in logs.** Layer 2 does not log attribute values.
- **Exported components.** The adapter-state receiver is registered with `RECEIVER_NOT_EXPORTED`. Receivers for broadcasts the Bluetooth process sends (bonds, ACL, discovery, audio) must be exported to hear it; they take only protected broadcasts, which other apps cannot send. The library manifest declares only `BackgroundScanReceiver`, not exported: the system reaches it through bt_kit's own mutable `PendingIntent`. The optional `CompanionPresenceService` and `CompanionDeviceServiceAdapter` services must be declared by the app with `android.permission.BIND_COMPANION_DEVICE_SERVICE`, which only the system holds.
- **Identifiers.** iOS gives each app its own peripheral UUIDs. Android MAC addresses of LE devices are often resolvable private addresses that rotate. Neither should be treated as a stable identity without bonding.
- **R8.** Consumer rules keep `dev.btkit.**`, which Dart reaches only through JNI.
