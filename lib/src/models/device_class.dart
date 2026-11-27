/// The Class of Device a Bluetooth Classic device reports: what kind of
/// device it is and which services it offers.
final class DeviceClass {
  const DeviceClass(this.value);

  /// The 24-bit Class of Device field.
  final int value;

  MajorDeviceClass get major => MajorDeviceClass.fromValue(value & 0x1f00);

  /// The major and minor class bits, as Android's `BluetoothClass.Device`
  /// constants define them.
  int get device => value & 0x1ffc;

  Set<DeviceService> get services => {
    for (final service in DeviceService.values)
      if (value & service.bit != 0) service,
  };

  @override
  bool operator ==(Object other) =>
      other is DeviceClass && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      'DeviceClass(0x${value.toRadixString(16).padLeft(6, '0')}, '
      '${major.name})';
}

enum MajorDeviceClass {
  miscellaneous(0x0000),
  computer(0x0100),
  phone(0x0200),
  networking(0x0300),
  audioVideo(0x0400),
  peripheral(0x0500),
  imaging(0x0600),
  wearable(0x0700),
  toy(0x0800),
  health(0x0900),
  uncategorized(0x1f00);

  const MajorDeviceClass(this.value);

  final int value;

  static MajorDeviceClass fromValue(int value) =>
      values.firstWhere((c) => c.value == value, orElse: () => uncategorized);
}

/// The service classes in a Class of Device.
enum DeviceService {
  limitedDiscoverability(0x002000),
  leAudio(0x004000),
  positioning(0x010000),
  networking(0x020000),
  rendering(0x040000),
  capturing(0x080000),
  objectTransfer(0x100000),
  audio(0x200000),
  telephony(0x400000),
  information(0x800000);

  const DeviceService(this.bit);

  final int bit;
}
