import 'dart:convert';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/app_uuids.dart';
import 'package:bt_radar/features/lab/profile/reference_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every characteristic has its own UUID in the Lab range', () {
    final uuids = {for (final c in ReferenceCharacteristic.values) c.uuid};
    expect(uuids, hasLength(ReferenceCharacteristic.values.length));
    expect(uuids, isNot(contains(ReferenceProfile.service)));
    expect(
      ReferenceCharacteristic.fixedValue.uuid,
      BluetoothUuid.parse('f3b1a101-6b2c-4e7a-9a54-7c2d8e0b1a00'),
    );
    expect(ReferenceCharacteristic.info.uuid, AppUuids.labUuid(0x10a));
  });

  test('properties match the documented profile', () {
    final echo = ReferenceCharacteristic.echo.properties;
    expect(echo.read && echo.write && echo.writeWithoutResponse, isTrue);
    expect(ReferenceCharacteristic.notifyStream.properties.bits, 0x10);
    expect(ReferenceCharacteristic.indicateStream.properties.bits, 0x20);
    expect(ReferenceCharacteristic.streamControl.properties.bits, 0x0a);
  });

  test('the long value is 512 bytes of i % 251', () {
    final value = ReferenceProfile.longValue;
    expect(value, hasLength(512));
    expect(value.take(3), [0, 1, 2]);
    expect(value[250], 250);
    expect(value[251], 0);
    expect(value[511], 511 % 251);
  });

  test('fixed values are the documented ASCII', () {
    expect(ascii.decode(ReferenceProfile.fixedValue), 'bt_kit lab v1');
    expect(ascii.decode(ReferenceProfile.encryptedValue), 'encrypted ok');
    expect(ascii.decode(ReferenceProfile.faultTargetValue), 'no fault');
  });

  group('info value', () {
    test('short descriptions are kept whole', () {
      final value = ReferenceProfile.infoValue('iOS 26.1.0');
      expect(ReferenceProfile.describeInfo(value), 'iOS 26.1.0');
    });

    test('long descriptions are cut at 64 bytes on a character boundary', () {
      final value = ReferenceProfile.infoValue('${'a' * 63}é tail');
      expect(value.length, lessThanOrEqualTo(ReferenceProfile.maxInfoLength));
      expect(ReferenceProfile.describeInfo(value), 'a' * 63);
    });
  });
}
