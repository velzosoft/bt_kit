/// The state of the local Bluetooth adapter.
enum AdapterState {
  /// Not known yet. On iOS the state is unknown until the app first asks
  /// for Bluetooth permission.
  unknown,

  /// The device has no usable Bluetooth hardware.
  unsupported,

  /// The app is not allowed to use Bluetooth.
  unauthorized,

  /// The system is resetting the Bluetooth stack (iOS).
  resetting,

  poweredOff,
  turningOn,
  poweredOn,
  turningOff;

  bool get isPoweredOn => this == poweredOn;
}
