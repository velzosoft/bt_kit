# Platform behavior and interop limits

Every quirk Layer 2 handles is listed with where it is handled.

## Android

| Behavior | Layer 2 handling |
|---|---|
| Only one GATT request may be in flight; a second one returns `false` or `ERROR_GATT_WRITE_REQUEST_BUSY`. This includes a request whose caller already timed out. | `OperationQueue` per peripheral, held until Android answers even after a timeout or cancellation; brief retry on busy writes (`AndroidGattClient._write`), which stops once the request is settled. |
| A `BluetoothGatt` that is not closed keeps a client slot, and slots run out after a few dozen. | Closed after every disconnection, failure or cancelled attempt. |
| `disconnect()` sometimes never reports `STATE_DISCONNECTED`. | Closed after a 5 s grace period. `connect()` waits for that disconnection to finish, so the grace period never closes a newer connection. |
| Connection failures surface as status `133` (`GATT_ERROR`), `8` (timeout), `19` or `22`. | `ConnectionException.nativeCode`; the caller decides whether to retry. |
| `onConnectionStateChange` statuses are HCI reasons without public constants: `8` supervision timeout, `19` remote user, `22` local host, `34` LL response timeout, `62` failed to establish, `147` connection timeout (API 35). | `androidDisconnectCause` maps them, with the link's state, to `DisconnectReason`; `nativeCode` keeps the status. Bluetooth turning off is reported as `adapterOff`. |
| A late `onConnectionStateChange` can arrive after the client was already closed as disconnected. | Ignored once the client is disconnected. |
| `onServiceChanged` (API 31+) says the database changed, not which services. | Every service is invalidated: it leaves `services`, and queued or later operations on it fail with `AttributeInvalidatedException`. The app rediscovers. |
| `requestConnectionPriority` has no public callback. | Completes once Android accepts the request. |
| `setPreferredPhy` may not call `onPhyUpdate` when the PHY does not change (to be confirmed on hardware). | After 3 s without it, the PHY is read with `readPhy`. |
| Android 14 and later negotiate an MTU of 517 on their own and report it unprompted. | `onMtuChanged` updates the MTU whether or not a request is pending. |
| Five scan starts within 30 s trigger silent throttling: the scan "runs" but reports nothing. | Starts are counted and the sixth waits for the window (`AndroidCentral._reserveScanStart`). |
| Unfiltered scans stop while the screen is off. | Documented on `ScanOptions.services` and `AdvertisementFilter.nameContains`. |
| `ScanFilter` has no substring match, takes only upper-case MAC addresses, and needs a mask as long as the data. | `androidNativeFilters` passes everything else to the controller; a filter with nothing native leaves the scan unfiltered. Every result is checked in Dart again. |
| Scans use only the LE 1M PHY unless told otherwise, missing long-range (Coded) advertisers. | Scans are extended (`setLegacy(false)`) on every supported PHY (`PHY_LE_ALL_SUPPORTED`). `ScanOptions.legacyOnly` and `phy` narrow them; `ScanPhy.leCoded` on an adapter without it fails with `UnsupportedFeatureException`. |
| Apps that declare `BLUETOOTH_SCAN` with `neverForLocation` do not get some results, such as beacons. Without the flag, results arrive only while the app holds `ACCESS_FINE_LOCATION` and location services are on; otherwise the scan reports nothing (to be confirmed on hardware for each kind of result). | `AndroidPermissions` reads the flag from `requestedPermissionsFlags`; without it, scans and the default `requestPermissions()` include `BluetoothPermission.location`. Location services are not checked. |
| The GATT cache can only be cleared through `BluetoothGatt.refresh()`, which the SDK hides; it is on the non-SDK list Android allows today, and a later release may block it. | `clearGattCache` calls it through JNI, and returns false and logs a warning if the lookup or call fails. The services are invalidated without a `servicesChanged` event. |
| Included services come from the same discovery; `getServices()` also lists secondary services. | `GattService.includedServices` resolves them by instance ID. |
| The scanner reports every match; first-match callbacks depend on hardware filters. | Duplicates are filtered in Dart (`ScanSessions`, after the filters) unless `allowDuplicates` is set. |
| `getName()` and most device calls throw `SecurityException` without `BLUETOOTH_CONNECT`. | `guardJni` maps it to `BluetoothPermissionException`. |
| Notifications need both `setCharacteristicNotification` and a CCCD write. | `setNotifying` does both, with the mode asked for, or indication when notify is not supported. |
| `connectGatt(Context, …)` is deprecated in API 37 in favour of a settings-based overload, which does not exist before API 37. | Layer 2 uses the API 33 overload; Layer 1 exposes both. |
| Permission results and `ACTION_REQUEST_ENABLE` results only reach an `Activity`. | `ActivityBridge` + `BtKitPlugin`. |

### Android peripheral role and L2CAP

| Behavior | Layer 2 handling |
|---|---|
| The GATT server does not track subscriptions. | Every notifying characteristic gets a CCCD; its writes are tracked per central and reported as subscriptions (`AndroidGattServer`). |
| Services must be added one at a time, each after `onServiceAdded`. | `GattServer` queues service changes. |
| Long writes arrive as prepared-write pieces, then `onExecuteWrite`. | Pieces are buffered per central and delivered as one write at execution. A rejected queue changes nothing. |
| Only one notification per central may be in flight. | Per-central queue; the next waits for `onNotificationSent`; brief retry on `ERROR_GATT_WRITE_REQUEST_BUSY`. |
| `onConnectionStateChange` also reports links this app opened as a central. | Such devices appear in `GattServer.centrals` too. |
| A custom local name cannot be advertised, only the system Bluetooth name. | `localName` fails with `UnsupportedFeatureException`; use `includeDeviceName`. |
| Legacy advertisements carry 31 bytes; extended connectable ones cannot have a scan response. | Legacy puts the name in the scan response; extended puts everything in the advertisement. `DATA_TOO_LARGE` becomes an `AdvertisingException` that says so. |
| A running advertising set can change its data, but its parameters only while disabled; data changed while enabled carries at most 251 bytes. | `AdvertisingSession.update` changes the data in place when only content changes; otherwise it starts a new set and stops the old one once the new one runs, which needs a free advertising slot. A failed update leaves the old set running. |
| Periodic advertising needs an extended, non-connectable, non-scannable set; its transmit power comes from `PeriodicAdvertisingParameters`, not the data, and its interval is in 1.25 ms units from 100 ms to 81.9 s. Phones cannot synchronize to it through public APIs. | `checkAdvertising` refuses other combinations with `ArgumentError`; `AndroidAdvertising` builds the parameters and the data. |
| A GATT server cannot ask for a connection priority. | `GattServer.requestConnectionPriority` fails with `UnsupportedFeatureException` (`capabilities.serverConnectionPriority`). |
| Included services are added to a service before it is added, as the `BluetoothGattService` the server already holds. | `GattServer` requires them to be added first and passes their native services. |
| `BluetoothSocket.connect`, `read`, `write` and `BluetoothServerSocket.accept` block. | Run on worker isolates (see [runtime.md](runtime.md#byte-channels-l2cap-rfcomm-and-accessory-sessions)). |
| `createL2capChannel` needs an encrypted link; `createInsecureL2capChannel` does not. | `secure` chooses between them. |

### Android bonding, Classic, companion devices and background

| Behavior | Layer 2 handling |
|---|---|
| `createBond` reports its outcome only through `ACTION_BOND_STATE_CHANGED`; a failure is `BONDING` followed by `NONE`. | `AndroidBond` waits for the first state after `BONDING`; anything but `BONDED` fails with `BondException`. |
| `createBond` returns `false` while pairing is already under way. | The pairing in progress is joined instead. |
| Bond, ACL, discovery and audio broadcasts come from the Bluetooth process, not the system server, and a receiver registered with `RECEIVER_NOT_EXPORTED` hears only the system server and its own app (to be confirmed on hardware). | These receivers are registered with `RECEIVER_EXPORTED`; every action they take is a protected broadcast, which no other app can send. The adapter-state receiver stays unexported, because the system server sends `ACTION_STATE_CHANGED`. |
| `cancelBondProcess` is public from API 37 only, and even there needs `BLUETOOTH_PRIVILEGED` for a pairing the app did not start. | Called on API 37 and later only; a refusal is logged and the caller still gets its timeout or cancellation. |
| `BluetoothDevice.removeBond()` is hidden and needs `BLUETOOTH_PRIVILEGED` once an app targets API 37. | `CompanionDeviceManager.removeBond` on API 36+, after creating an association if there is none; its presence is checked, since it arrived behind a feature flag. Elsewhere the Bluetooth settings open. |
| An association needs a system chooser, reported through `onAssociationPending` with an `IntentSender`. | Started through `ActivityBridge.startIntentSenderForResult`; a dismissed chooser returns null. |
| With a `Handler`, a dismissed chooser arrives only as `onFailure(CharSequence)` with `user_rejected` or `canceled`; the coded `onFailure` needs an `Executor`. | Both reasons count as a dismissal. |
| A `BluetoothDeviceFilter` matches bonded devices by address; LE filters only match devices that advertise. | Bond removal associates with an address filter; the picker uses LE filters for services and manufacturer data. |
| Name filters take a `java.util.regex.Pattern`, which Layer 1 keeps as a stub because the name clashes with `dart:core`. | Compiled through raw JNI (`Pattern.quote`, `Pattern.compile`). |
| `AssociationInfo.getDeviceMacAddress` returns `MacAddress`, outside the Bluetooth packages. | Read through its `toString`. |
| An inquiry reports results and its end only as broadcasts, and the end of an earlier inquiry can arrive right after a new one starts. | Only an `ACTION_DISCOVERY_FINISHED` after `ACTION_DISCOVERY_STARTED` ends the stream. |
| An RFCOMM connect during an inquiry is slow and often fails. | The inquiry is cancelled first. |
| `BluetoothClass` hides the full Class of Device; its `toString` prints it in hexadecimal. | `DeviceClass` is parsed from it. |
| `PendingIntent` scan results reach a manifest receiver, possibly in a fresh process, and the system adds the results as extras. | `BackgroundScanReceiver` gets an explicit, mutable `PendingIntent`; `BackgroundDelivery` hands the intent to Dart. |
| A process can be frozen once `onReceive` returns. | `goAsync()` keeps the receiver alive while a headless engine handles the event, which it acknowledges, for at most 9 s. A UI engine that listens gets the event and the receiver finishes at once. Without a registered handler, events are dropped instead of queued, and at most 64 wait for the headless engine. |
| The callback cache a headless engine starts from is only readable once Flutter is initialized. | `BackgroundDelivery` initializes the Flutter loader first. |
| API 36 reports presence through `onDevicePresenceEvent`; earlier versions call `onDeviceAppeared` and `onDeviceDisappeared`, and observe by address, which API 36 deprecates. | `CompanionPresenceService` maps both; `ObservingDevicePresenceRequest` is used on API 36+, the address before. |
| Profile proxies arrive asynchronously and hold a binder connection. | Opened per query and closed after it. A proxy that does not connect within 5 s counts as unavailable and is closed if it connects later. |
| Android 13 opens an LE Audio proxy even without LE Audio hardware, and it never connects. | LE Audio is skipped unless `isLeAudioSupported` says so. |
| A2DP reports playing separately from connecting, with its own state constants. | Both become `AudioConnection` changes. |
| `RangingManager` is reachable only by class, and sessions end with a reason code. | Looked up with `getSystemService(Class)`; reason codes become `RangingException` messages. |
| `RangingData`'s standard deviation arrived in API 36.1; on 36.0 the methods are missing. | Probed once; `standardDeviation` is null on 36.0. |
| An exception in a JNI callback handled with `$async` vanishes, and leaks a reference. | Broadcast, background and ranging handlers catch and log their errors and release their arguments. |
| ACL broadcasts report every link, LE and Classic, of every app. | `SystemConnectionEvent.transport` comes from `EXTRA_TRANSPORT`. |

### JNIgen limits

- Abstract classes cannot be implemented from Dart, hence the generated adapters.
- JDK classes (`UUID`, `InputStream` …) are summarized from bytecode, so their parameters are named `arg0`… and nullability is unknown.
- Stub sources imply default constructors that do not exist. The implicit-constructor rule removes them.
- Overloads get `$N` suffixes (`connectGatt$3`). The inventory's *Methods* column and the doc comment on each binding name the Java signature.
- A method newer than the device fails at call time with a JNI `NoSuchMethodError`. Check `Build$VERSION.SDK_INT`.
- Flutter prints *"The plugin bt_kit requires Android SDK version 37"*. The plugin compiles against API 37 so its adapters can override API 37 callbacks, but the AAR allows any app compileSdk from 33, and builds succeed with Flutter's defaults. Raising the app's `compileSdk` to 37 removes the warning. The target SDK never needs to change.

## iOS

| Behavior | Layer 2 handling |
|---|---|
| Creating `CBCentralManager` shows the permission prompt. | Created only when permission is requested or already granted. |
| The manager reports `unknown` briefly after creation. | `settledAdapterState` waits up to 3 s. |
| Delegate properties are weak. | Each client owns its delegate. |
| A read result and a notification arrive through the same callback. | A value completes a read only while a read of that characteristic is pending. |
| A write without response has no callback and can be refused while the buffer is full. | Waits for `canSendWriteWithoutResponse` / `peripheralIsReadyToSendWriteWithoutResponse`. |
| Writing the CCCD descriptor raises an Objective-C exception. | Refused with `UnsupportedFeatureException`; use `subscribe()`. |
| Connections never time out. | Layer 2's timeout cancels the attempt. |
| When Bluetooth turns off, every connection drops without `centralManager:didDisconnectPeripheral:error:`. | `IosCentral` ends the links itself, with `DisconnectCause.adapterOff`. |
| Disconnection errors are `CBError`s: `6` connection timeout, `7` peripheral disconnected, `10` connection failed; no error when the app cancelled. | `iosDisconnectCause` maps them to `DisconnectReason`. |
| `peripheral:didModifyServices:` lists only the invalidated services; adding a service may invalidate none. | Only those leave `services` and fail with `AttributeInvalidatedException`; `servicesChanged` fires either way. |
| There is no MTU callback. | `mtu` is `maximumWriteValueLengthForType:withoutResponse` + 3; `mtuChanges` reports it once after connecting. |
| `setNotifyValue` picks notification or indication itself. | A specific `NotifyMode` fails with `UnsupportedFeatureException` when the characteristic supports both. |
| PHY and connection priority are not exposed to centrals. | `capabilities.phy` and `connectionPriority` are false; the calls fail with `UnsupportedFeatureException`. |
| Only service UUIDs can be scanned for natively. | When every filter names a service, the union is passed to `scanForPeripheralsWithServices`; otherwise the scan runs with `nil`, which stops in the background, and filters are checked in Dart. |
| Discovery takes three rounds of callbacks, and finds primary services only. Secondary services are reachable only as included services, which take a round of their own. | Collapsed into one `discoverServices()`, which discovers included services before characteristics and adds the ones it has not seen to `services`. They are matched by object identity, which assumes CoreBluetooth hands back the same `CBService` (to be confirmed on hardware). |
| There is no GATT cache API; CoreBluetooth follows Services Changed itself. | `capabilities.gattCacheRefresh` is false; `clearGattCache` fails with `UnsupportedFeatureException`. |
| There is no API for the device's Bluetooth name. | `capabilities.adapterName` is false. |
| CoreBluetooth never needs the location permission. | `BluetoothPermission.location` is reported as granted, and requesting it alone shows no prompt. |
| A new `scanForPeripherals` call replaces the running scan. | `ScanSessions` shares one scan and refuses a second with different options. |
| Descriptor values arrive as `NSData`, `NSNumber` or `NSString`. | Converted to bytes (`bytesOf`). |
| Peripheral identifiers are per-app UUIDs, not MAC addresses. | `Peripheral.id` documents it. |
| `retrieveConnectedPeripherals` needs at least one service UUID. | Documented on `systemPeripherals`. |

### iOS peripheral role and L2CAP

| Behavior | Layer 2 handling |
|---|---|
| One `CBPeripheralManager` runs the server, advertising and L2CAP; one server and one advertisement per app. | `IosPeripheralRole` routes the delegate; a second server or advertisement fails clearly. |
| A characteristic created with a value is cached and read-only. | Characteristics are created without a value, so every read reaches Dart and values can change. |
| Only User Description and Presentation Format descriptors, with fixed values. | Other descriptors, or ones with handlers, fail with `UnsupportedFeatureException`. |
| Broadcast is not allowed on local characteristics. | Fails with `UnsupportedFeatureException`. |
| A long write arrives as several requests in one callback; only the first is answered. | The pieces are joined into one write; the first request gets the result. |
| The callback does not say whether a write expects a response. | A response is sent when the characteristic allows writes with response. |
| `updateValue` returns `NO` while the transmit queue is full. | Retried after `peripheralManagerIsReadyToUpdateSubscribers`. A notification completes once queued. |
| There are no connection events for centrals. | A central appears in `GattServer.centrals` with its first request or subscription. |
| Advertising carries only a local name and service UUIDs, always connectable, and only in the foreground. Service UUIDs move to an overflow area in the background, visible only to iOS scanners that ask for them. There is no periodic advertising. | Other options fail with `UnsupportedFeatureException`. |
| A running advertisement cannot be changed. | `AdvertisingSession.update` stops it and starts the new one; if that fails, the previous one is started again. |
| `setDesiredConnectionLatency:forCentral:` takes a latency, not a priority, and reports nothing. | `GattServer.requestConnectionPriority` maps `high` to low latency, `balanced` to medium and `lowPower` to high, and completes at once. |
| `CBMutableService.includedServices` must name services already added. | `GattServer` requires them to be added first. |
| L2CAP channels are `NSStream` pairs that need a run loop, and the channel closes when released. | Scheduled on the main run loop; open channels are kept until closed. |
| `openL2CAPChannel` has no security choice; the publishing side decides with `publishL2CAPChannelWithEncryption`. | `secure` is ignored when opening on iOS. |

### iOS accessories, restoration and ranging

| Behavior | Layer 2 handling |
|---|---|
| ExternalAccessory reports connections only as `NSNotification`s, and only after `registerForLocalNotifications`. | Observed while `accessories.changes` has listeners. |
| `EASession` returns nil when the protocol is missing from `UISupportedExternalAccessoryProtocols` or already has a session. | `NativeOperationException` that says so. |
| AccessorySetupKit reports everything through one event handler on a dispatch queue; the chosen accessory arrives as `accessoryAdded`, the end of the picker as `pickerDidDismiss`. | `IosCompanion` collects the added accessory until the picker closes; the session runs on the main dispatch queue (`_dispatch_main_q`). |
| Each picker item needs a product image. | A system symbol stands in when the app gives none. |
| A discovery descriptor needs a service UUID or a company identifier, listed in `Info.plist`. | `ArgumentError` otherwise. |
| Apps that reach devices only through AccessorySetupKit need no Bluetooth usage description. | `NSAccessorySetupKitSupports` counts as declared. |
| `centralManager:willRestoreState:` arrives right after the manager is created, and only then; restored peripherals must get their delegate inside it, or the events that woke the app are lost. | `BtKit.configure` creates the managers at once when authorized. `willRestoreState` runs synchronously on the main thread (a blocking delegate method, called directly on the isolate's thread); `BtKit.restored` replays the restoration to later listeners. |
| Restored services stay published; adding them again would publish them twice. | The server adopts a restored service with the same UUID and characteristics; a mismatched one is removed. |
| `registerForConnectionEventsWithOptions:` keeps one set of options per manager and has no way to unregister. | One registration serves every listener; cancelling registers an empty peripheral list. |
| Channel Sounding delegate methods exist from iOS 27; implementing them on older versions throws. | Added to the delegate only where the protocol has them. |
| A cancelled Channel Sounding session reports its completion later, possibly after a new one started. | Completions and results of cancelled sessions are ignored. |
| There is no bonding API and no audio profile state. | `capabilities.bonding` and `audioProfiles` are false; the calls fail with `UnsupportedFeatureException`. |

### FFIgen limits

- Handler names follow Objective-C selectors (`centralManager_didConnectPeripheral_`).
- Listener delegates cannot return values. No Bluetooth delegate method needs one.
- Swift-only APIs are not reachable. All three frameworks are Objective-C, so nothing is lost today.
- Block parameters still have FFIgen's `fromFunction`, `listener` and `blocking` constructors. Use `listener`, which is safe on any thread.
- A delegate method newer than the running iOS cannot be implemented: `implement` throws `FailedToLoadProtocolMethodException`. Check `<Protocol>$Builder.<method>.isAvailable` first.
- `dispatch_get_main_queue()` is a macro; Layer 1 code that needs a queue object can look up the `_dispatch_main_q` symbol, as Layer 2 does.

## Required app configuration

**Android** `AndroidManifest.xml` (the app's `minSdk` must be 33 or higher):

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Only for the peripheral role: -->
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<!-- Only for scan results that reveal location, such as beacons: drop
     neverForLocation above and declare this. Scans then need it. -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<!-- Only for measureDistance (Android 16 and later): -->
<uses-permission android:name="android.permission.RANGING" />
<!-- Only for companion presence: -->
<uses-permission android:name="android.permission.REQUEST_OBSERVE_COMPANION_DEVICE_PRESENCE" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />

<application>
  <!-- Only for companion presence, also while the app is not running: -->
  <service
      android:name="dev.btkit.CompanionPresenceService"
      android:exported="true"
      android:permission="android.permission.BIND_COMPANION_DEVICE_SERVICE">
    <intent-filter>
      <action android:name="android.companion.CompanionDeviceService" />
    </intent-filter>
  </service>
</application>
```

The library manifest adds `dev.btkit.BackgroundScanReceiver` (not exported) for background scans, and declares `android.software.companion_device_setup` (not required), without which `CompanionDeviceManager` refuses the companion picker and `removeBond()`. Apps declare nothing for either.

**iOS** `Info.plist` (deployment target 18.0 or later):

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Connects to your devices.</string>
<!-- Background use: -->
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
</array>
<!-- ExternalAccessory: every protocol the app speaks -->
<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.example.sensor</string>
</array>
<!-- AccessorySetupKit: the services or company identifiers the picker
     looks for -->
<key>NSAccessorySetupKitSupports</key>
<array>
  <string>Bluetooth</string>
</array>
<key>NSAccessorySetupBluetoothServices</key>
<array>
  <string>180D</string>
</array>
```

State restoration needs the background modes above and `BtKit.configure` with a restore identifier as the first call in `main`.
