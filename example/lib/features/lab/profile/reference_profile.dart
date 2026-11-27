import 'dart:convert';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import '../../../bluetooth/app_uuids.dart';

/// The characteristics of the Lab reference profile.
enum ReferenceCharacteristic {
  fixedValue(0x101, 'Fixed value', CharacteristicProperties.of(read: true)),
  echo(
    0x102,
    'Echo',
    CharacteristicProperties.of(
      read: true,
      write: true,
      writeWithoutResponse: true,
    ),
  ),
  notifyStream(
    0x103,
    'Notify stream',
    CharacteristicProperties.of(notify: true),
  ),
  indicateStream(
    0x104,
    'Indicate stream',
    CharacteristicProperties.of(indicate: true),
  ),
  longValue(0x105, 'Long value', CharacteristicProperties.of(read: true)),
  encrypted(0x106, 'Encrypted value', CharacteristicProperties.of(read: true)),
  faultControl(
    0x107,
    'Fault control',
    CharacteristicProperties.of(read: true, write: true),
  ),
  faultTarget(0x108, 'Fault target', CharacteristicProperties.of(read: true)),
  streamControl(
    0x109,
    'Stream control',
    CharacteristicProperties.of(read: true, write: true),
  ),
  info(0x10a, 'Info', CharacteristicProperties.of(read: true)),
  databaseControl(
    0x10b,
    'Database control',
    CharacteristicProperties.of(read: true, write: true),
  );

  const ReferenceCharacteristic(this.id, this.label, this.properties);

  final int id;
  final String label;
  final CharacteristicProperties properties;

  BluetoothUuid get uuid => AppUuids.labUuid(id);
}

abstract final class ReferenceProfile {
  static final service = AppUuids.lab;

  /// The name an iOS reference advertises. Android advertises the phone's
  /// Bluetooth name instead.
  static const localName = 'bt_kit Lab';

  static final fixedValue = _ascii('bt_kit lab v1');
  static final encryptedValue = _ascii('encrypted ok');
  static final faultTargetValue = _ascii('no fault');

  /// Byte `i` is `i % 251`, so a piece read at the wrong offset never
  /// matches: 251 is prime and shares no period with any ATT MTU.
  static final longValue = Uint8List.fromList([
    for (var i = 0; i < LocalAttribute.maxLength; i++) i % 251,
  ]);

  /// The service the reference adds and removes on request, with one
  /// readable characteristic; see [DatabaseCommand].
  static final extraService = AppUuids.labUuid(0x110);
  static final extraCharacteristic = AppUuids.labUuid(0x111);
  static final extraValue = _ascii('extra');

  /// The secondary service the Lab service includes, with one readable
  /// characteristic.
  static final includedService = AppUuids.labUuid(0x120);
  static final includedCharacteristic = AppUuids.labUuid(0x121);
  static final includedValue = _ascii('included');

  /// Manufacturer data a reference advertises where it can: the company
  /// identifier the Bluetooth SIG reserves for tests, and one byte.
  static const manufacturerId = 0xffff;
  static final manufacturerData = Uint8List.fromList([0x4c]);

  static const maxInfoLength = 64;
  static const maxRateHz = 1000;

  /// The Info value: who serves the profile, as UTF-8 of at most
  /// [maxInfoLength] bytes.
  static Uint8List infoValue(String description) {
    final bytes = utf8.encode(description);
    if (bytes.length <= maxInfoLength) return bytes;
    var end = maxInfoLength;
    while (end > 0 && bytes[end] & 0xc0 == 0x80) {
      end--;
    }
    return Uint8List.sublistView(bytes, 0, end);
  }

  static String describeInfo(List<int> value) =>
      utf8.decode(value, allowMalformed: true);

  static Uint8List _ascii(String text) =>
      Uint8List.fromList(ascii.encode(text));
}
