/// A Bluetooth capability the user grants at runtime.
///
/// Android has a separate runtime permission for each. iOS has a single
/// Bluetooth authorization that covers all of them.
enum BluetoothPermission {
  /// Discover nearby devices. Android: `BLUETOOTH_SCAN`.
  scan,

  /// Connect to and communicate with devices. Android: `BLUETOOTH_CONNECT`.
  connect,

  /// Advertise to nearby devices. Android: `BLUETOOTH_ADVERTISE`.
  advertise,

  /// Measure the distance to nearby devices. Android 16 (API 36) and
  /// later: `RANGING`.
  ranging,

  /// Receive scan results that reveal the location. Android:
  /// `ACCESS_FINE_LOCATION`.
  ///
  /// Android withholds some results, such as beacons, from apps that
  /// declare `BLUETOOTH_SCAN` with `neverForLocation`. An app that needs
  /// them drops the flag and declares this permission; its scans then need
  /// it, and Location turned on. iOS reports it granted: CoreBluetooth never
  /// needs it.
  location,
}

enum PermissionStatus {
  granted,

  /// Not requested yet.
  notDetermined,

  /// Denied, and asking again may show the system prompt.
  denied,

  /// Denied in a way only the system settings can change.
  permanentlyDenied,

  /// Blocked by device policy, such as parental controls (iOS).
  restricted,

  /// The app does not declare the permission in its `AndroidManifest.xml`
  /// or the usage description in its `Info.plist`.
  notDeclared;

  bool get isGranted => this == granted;
}
