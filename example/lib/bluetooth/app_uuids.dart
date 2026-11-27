import 'package:bt_kit/bt_kit.dart';

/// The 128-bit UUIDs this app defines for its own services.
abstract final class AppUuids {
  /// Advertised by a phone in beacon mode, so it can be a Hunt target.
  static final beacon = _uuid(0x001);

  /// A Hunt party hosted by another phone.
  static final party = _uuid(0x010);
  static final partyGame = _uuid(0x011);
  static final partyState = _uuid(0x012);
  static final partyFinish = _uuid(0x013);

  /// File beam: the receiver serves its L2CAP PSM here.
  static final fileBeam = _uuid(0x020);
  static final fileBeamPsm = _uuid(0x021);

  /// Hello board: an ESP32 with a button and an LED.
  static final board = _uuid(0x030);
  static final boardButton = _uuid(0x031);
  static final boardLedCommand = _uuid(0x032);
  static final boardLed = _uuid(0x033);
  static final boardInfo = _uuid(0x034);

  /// The Lab reference peripheral profile.
  static final lab = _uuid(0x100);

  static BluetoothUuid _uuid(int id) => BluetoothUuid.parse(
    'f3b1a${id.toRadixString(16).padLeft(3, '0')}-6b2c-4e7a-9a54-7c2d8e0b1a00',
  );

  /// A UUID in the Lab profile's range, such as `labUuid(0x101)`.
  static BluetoothUuid labUuid(int id) => _uuid(id);
}
