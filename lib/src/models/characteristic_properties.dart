/// The properties of a GATT characteristic, as defined by the Bluetooth
/// Core Specification. Both platforms use the same bit values.
extension type const CharacteristicProperties(int bits) {
  const CharacteristicProperties.of({
    bool broadcast = false,
    bool read = false,
    bool writeWithoutResponse = false,
    bool write = false,
    bool notify = false,
    bool indicate = false,
  }) : bits =
           (broadcast ? _broadcast : 0) |
           (read ? _read : 0) |
           (writeWithoutResponse ? _writeWithoutResponse : 0) |
           (write ? _write : 0) |
           (notify ? _notify : 0) |
           (indicate ? _indicate : 0);

  static const _broadcast = 0x01;
  static const _read = 0x02;
  static const _writeWithoutResponse = 0x04;
  static const _write = 0x08;
  static const _notify = 0x10;
  static const _indicate = 0x20;
  static const _authenticatedSignedWrites = 0x40;
  static const _extendedProperties = 0x80;

  bool get broadcast => bits & _broadcast != 0;
  bool get read => bits & _read != 0;
  bool get writeWithoutResponse => bits & _writeWithoutResponse != 0;
  bool get write => bits & _write != 0;
  bool get notify => bits & _notify != 0;
  bool get indicate => bits & _indicate != 0;
  bool get authenticatedSignedWrites => bits & _authenticatedSignedWrites != 0;
  bool get extendedProperties => bits & _extendedProperties != 0;
}
