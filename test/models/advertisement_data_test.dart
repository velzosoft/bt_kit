import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the common advertising data types', () {
    final bytes = Uint8List.fromList([
      ...[0x02, 0x01, 0x06],
      ...[0x03, 0x03, 0x0d, 0x18],
      ...[0x05, 0x09, 0x42, 0x54, 0x2d, 0x31],
      ...[0x02, 0x0a, 0xf4],
      ...[0x05, 0x16, 0x0f, 0x18, 0x55, 0x01],
      ...[0x05, 0xff, 0x4c, 0x00, 0x02, 0x15],
      ...[0x03, 0x19, 0x41, 0x03],
    ]);
    final data = AdvertisementData.parse(bytes, isConnectable: true);
    expect(data.flags, 0x06);
    expect(data.serviceUuids, [BluetoothUuid.short(0x180d)]);
    expect(data.localName, 'BT-1');
    expect(data.txPowerLevel, -12);
    expect(data.serviceData[BluetoothUuid.short(0x180f)], [0x55, 0x01]);
    expect(data.manufacturerData[0x004c], [0x02, 0x15]);
    expect(data.appearance, 0x0341);
    expect(data.isConnectable, isTrue);
  });

  test('prefers the complete local name over the shortened one', () {
    final data = AdvertisementData.parse(
      Uint8List.fromList([0x02, 0x08, 0x41, 0x03, 0x09, 0x41, 0x42]),
    );
    expect(data.localName, 'AB');
  });

  test('parses 128-bit service UUIDs', () {
    final uuid = BluetoothUuid.parse('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
    final bytes = Uint8List.fromList([
      0x11,
      0x07,
      ...[
        for (var i = 15; i >= 0; i--)
          int.parse(
            uuid.value.replaceAll('-', '').substring(i * 2, i * 2 + 2),
            radix: 16,
          ),
      ],
    ]);
    expect(AdvertisementData.parse(bytes).serviceUuids, [uuid]);
  });

  test('stops at a malformed structure instead of throwing', () {
    final data = AdvertisementData.parse(
      Uint8List.fromList([0x02, 0x01, 0x06, 0x09, 0xff, 0x01]),
    );
    expect(data.flags, 0x06);
    expect(data.manufacturerData, isEmpty);
  });
}
