# Binding generation and callback integration

```sh
dart run tool/generate.dart          # both platforms
dart run tool/generate.dart android  # needs the Android SDK platform android-37.0
dart run tool/generate.dart ios      # needs Xcode with an iOS 26+ SDK
```

Both generators are Dart programs that use the JNIgen and FFIgen Dart APIs (the YAML formats are deprecated). Re-running them is deterministic. CI regenerates and fails on any diff (see [testing.md](testing.md)).

## Android (JNIgen)

`tool/android/generate_android.dart` runs these steps:

1. **Locate the SDK** (`android_sdk.dart`) through `ANDROID_HOME`, `ANDROID_SDK_ROOT` or the default locations, and extract the stub sources for the packages in scope.
2. **Load API levels** (`api_levels.dart`) from `data/api-versions.xml`: since and deprecated levels for every class, method and field.
3. **Summarize** the inputs once with JNIgen's API summarizer. Android classes come from stub sources, which keep parameter names, Javadoc and `@NonNull`/`@Nullable`. JDK classes, which the Java module system keeps out of a source path, come from `android.jar` bytecode. The Flutter SDK's `flutter.jar` is on the class path too, because `BackgroundDelivery` starts Flutter engines.
4. **Find callback classes** (`callback_classes.dart`) and **write a Java adapter** for each (`java_adapters.dart`) into `android/src/main/java/dev/btkit/adapters`.
5. **Generate, pass 1**: JNIgen runs with the exposure rules applied as visitors (`exposure_visitors.dart`). JNIgen's visitors see names but not signatures, so one visitor records arities and a second applies the rules.
6. **Build the `implement` factories** (`callback_facades.dart`). Handler types are copied from the listener bindings that pass 1 generated, so they always match.
7. **Generate, pass 2**: the same run, with each factory added to its callback class through `customClassBody`.
8. **Write the libraries and inventory**: `lib/android.dart` hides plumbing and `dart:core` collisions, `lib/src/native/android/bindings.dart` is the barrel Layer 2 imports, and `doc/inventory/android.md` records every decision.

Output is a single `bindings.g.dart`, so each factory can reach its adapter without imports.

### Callbacks

There are two shapes, one per kind of Java callback.

**Interfaces** such as `BluetoothProfile.ServiceListener`, `RangingSession.Callback` or `Executor` use JNIgen's own API. Every method is required, as in Java:

```dart
final listener = BluetoothProfile$ServiceListener.implement(
  $BluetoothProfile$ServiceListener(
    onServiceConnected: (profile, proxy) {},
    onServiceDisconnected: (profile) {},
  ),
);
```

**Abstract classes** such as `BluetoothGattCallback`, `ScanCallback` or `BroadcastReceiver` cannot be implemented by JNIgen. Each one gets a generated Java adapter:

```java
public final class ScanCallbackAdapter extends android.bluetooth.le.ScanCallback {
  public interface Listener { void onScanResult(int callbackType, ScanResult result); ... }
  public ScanCallbackAdapter(Listener listener) { ... }
  @Override public void onScanResult(int callbackType, ScanResult result) {
    btKitListener.onScanResult(callbackType, result);
  }
}
```

Dart implements `Listener` and the generated factory puts it behind the callback's own type. Every handler is optional, as overriding is in Java:

```dart
final callback = BluetoothGattCallback.implement(
  onConnectionStateChange: (gatt, status, newState) {},
  onCharacteristicChanged: (gatt, characteristic, value) {},
);
device.connectGatt$3(context, false, callback, BluetoothDevice.TRANSPORT_LE, BluetoothDevice.PHY_LE_1M_MASK);
```

- Adapters forward every non-deprecated callback, including ones newer than the running device. The system never calls those, so no version check is needed.
- Adapters do not call `super`. The base classes forward new overloads to deprecated ones (for example `onCharacteristicRead` with and without a value); skipping `super` keeps each event single.
- Handlers are registered with `$async: true`. Java posts the call to the Dart isolate and returns at once, so a binder thread never waits on Dart.
- **Services** (`CompanionDeviceService`) are created by the system with no arguments. Their adapter reads a static listener, which `implement` installs; `running` returns the live instance. The app declares the adapter in its manifest.
- **Activity results** come from the `ActivityBridge` and `BtKitPlugin` pair. It is internal plumbing used by Layer 2.
- **Background events** come from `BackgroundDelivery`, bound like `ActivityBridge` and hidden from `android.dart`. `BackgroundScanReceiver` (declared in the library manifest, not exported) and `CompanionPresenceService` (declared by apps that observe presence) hand it their events; it passes them to the engine that listens, or starts a headless engine for the app's registered handler. The Layer 1 `CompanionDeviceServiceAdapter` stays available for apps that want the raw callbacks.

## iOS (FFIgen)

`tool/ios/generate_ios.dart` runs these steps:

1. Parse `src/ios/bt_kit.h` (the three framework umbrella headers) against the iOS SDK that `xcrun` reports, targeting `arm64-apple-ios18.0`.
2. **Generate, pass 1** with the exposure rules as visitors and `externalVersions: ios >= 18.0`.
3. **Find system-created classes** in the output. FFIgen drops unavailable initializers after visitors run, so the classes left without an `init*` are read from pass 1.
4. **Generate, pass 2** with their allocators removed.
5. **Add one `implement` factory per protocol** (`delegate_facades.dart`) that forwards to `$Builder.implementAsListener`.
6. **Write the libraries and inventory**: `lib/ios.dart` hides `$Builder` and the delegate-invocation extensions, plus `lib/src/native/ios/bindings.dart` and `doc/inventory/ios.md`.

```dart
final delegate = CBCentralManagerDelegate.implement(
  centralManagerDidUpdateState_: (central) {},
  centralManager_didDiscoverPeripheral_advertisementData_RSSI_: (c, p, ad, rssi) {},
);
final central = CBCentralManager.alloc().initWithDelegate(delegate, queue: null);
```

Handler names follow the Objective-C selectors, which is FFIgen's convention.

A delegate method newer than the running iOS cannot be implemented: the protocol has no signature for it, and `implement` throws `FailedToLoadProtocolMethodException`. Pass such handlers only when `<Protocol>$Builder.<method>.isAvailable` holds, as Layer 2 does for the iOS 27 Channel Sounding callbacks.

### Why listener semantics

Listener blocks can be called on any thread. The trampoline retains the arguments and posts the call to the Dart isolate. CoreBluetooth delegate methods all return `void`, so nothing needs a synchronous answer. The other FFIgen modes would either crash when called from the wrong thread or block CoreBluetooth's queue on Dart. Completion-handler blocks (AccessorySetupKit, ExternalAccessory) use the generated `ObjCBlock_*.listener` constructors for the same reason.

### Native build

FFIgen writes the trampolines to `src/ios/bindings.g.m`. `hook/build.dart` compiles them with `native_toolchain_c` for iOS targets only, linking CoreBluetooth, AccessorySetupKit and ExternalAccessory. The asset name equals the Dart library that declares the `@Native` symbols (`src/native/ios/bindings.g.dart`), so they resolve without an asset id. Class lookups resolve through the same dylib, which loads the frameworks. Native assets are on by default in current Flutter, so there is no podspec and no Swift package.
