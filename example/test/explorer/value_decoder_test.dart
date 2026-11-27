import 'dart:convert';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/explorer/value_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

String? characteristic(int uuid, List<int> bytes) =>
    ValueDecoder.characteristic(BluetoothUuid.short(uuid), bytes);

String? descriptor(int uuid, List<int> bytes) =>
    ValueDecoder.descriptor(BluetoothUuid.short(uuid), bytes);

void main() {
  group('printableText', () {
    test('decodes printable UTF-8', () {
      expect(ValueDecoder.printableText(utf8.encode('Grüße 👋')), 'Grüße 👋');
    });

    test('drops trailing NUL bytes', () {
      expect(ValueDecoder.printableText([0x48, 0x69, 0, 0]), 'Hi');
    });

    test('rejects control characters and invalid UTF-8', () {
      expect(ValueDecoder.printableText([0x48, 0x01]), isNull);
      expect(ValueDecoder.printableText([0xff, 0xfe]), isNull);
      expect(ValueDecoder.printableText([0, 0]), isNull);
      expect(ValueDecoder.printableText([]), isNull);
    });

    test('keeps tabs and line breaks', () {
      expect(ValueDecoder.printableText(utf8.encode('a\tb\r\n')), 'a\tb\r\n');
    });
  });

  group('characteristics', () {
    test('Battery Level', () {
      expect(characteristic(0x2a19, [87]), '87 %');
    });

    test('Device Information strings and Device Name', () {
      expect(characteristic(0x2a29, utf8.encode('Polar\x00')), '“Polar”');
      expect(characteristic(0x2a00, utf8.encode('H10 9A2B')), '“H10 9A2B”');
      expect(characteristic(0x2a26, [0]), isNull);
    });

    test('Appearance', () {
      expect(characteristic(0x2a01, [0xc1, 0x00]), 'Watch (0x00C1)');
      expect(
        characteristic(0x2a01, [0x40, 0x03]),
        'Heart rate sensor (0x0340)',
      );
      expect(characteristic(0x2a01, [0xc0, 0xff]), 'Unknown (0xFFC0)');
    });

    test('Heart Rate Measurement', () {
      expect(characteristic(0x2a37, [0x00, 72]), '72 bpm');
      expect(characteristic(0x2a37, [0x01, 0x2c, 0x01]), '300 bpm');
      expect(characteristic(0x2a37, [0x06, 64]), '64 bpm');
      expect(characteristic(0x2a37, [0x04, 64]), '64 bpm · no skin contact');
      expect(characteristic(0x2a37, [0x01, 0x2c]), isNull);
    });

    test('Tx Power Level is signed', () {
      expect(characteristic(0x2a07, [0xfc]), '-4 dBm');
    });

    test('Temperature and Humidity', () {
      expect(characteristic(0x2a6e, [0x69, 0x08]), '21.53 °C');
      expect(characteristic(0x2a6e, [0x0c, 0xfe]), '-5 °C');
      expect(characteristic(0x2a6f, [0x88, 0x13]), '50 %');
    });

    test('Temperature Measurement uses an IEEE 11073 FLOAT', () {
      expect(characteristic(0x2a1c, [0x00, 0x42, 0x0e, 0x00, 0xfe]), '36.5 °C');
      expect(characteristic(0x2a1c, [0x01, 0x3d, 0x00, 0x00, 0x00]), '61 °F');
    });

    test('Current Time', () {
      expect(
        characteristic(0x2a2b, [0xea, 0x07, 11, 25, 14, 3, 7, 3, 0, 0]),
        '2026-11-25 14:03:07',
      );
      expect(characteristic(0x2a2b, [0, 0, 0, 0, 0, 0, 0]), isNull);
    });

    test('Peripheral Preferred Connection Parameters', () {
      expect(
        characteristic(0x2a04, [6, 0, 12, 0, 0, 0, 0x90, 0x01]),
        'Interval 7.5–15 ms · latency 0 · timeout 4000 ms',
      );
    });

    test('PnP ID names Bluetooth SIG companies', () {
      expect(
        characteristic(0x2a50, [1, 0x4c, 0, 0x02, 0x20, 0x00, 0x01]),
        'Apple 0x004C · product 0x2002 · version 0x0100',
      );
      expect(
        characteristic(0x2a50, [2, 0x6d, 0x04, 0x01, 0x00, 0x00, 0x01]),
        'USB vendor 0x046D · product 0x0001 · version 0x0100',
      );
    });

    test('Alert Level and Body Sensor Location', () {
      expect(characteristic(0x2a06, [2]), 'High alert');
      expect(characteristic(0x2a38, [1]), 'Chest');
      expect(characteristic(0x2a38, [9]), isNull);
    });

    test('too short values are not decoded', () {
      expect(characteristic(0x2a19, []), isNull);
      expect(characteristic(0x2a04, [6, 0, 12]), isNull);
    });

    test('unknown values fall back to quoted text of two or more bytes', () {
      final vendor = BluetoothUuid.parse(
        '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
      );
      expect(ValueDecoder.characteristic(vendor, utf8.encode('ok')), '“ok”');
      expect(ValueDecoder.characteristic(vendor, [0x41]), isNull);
      expect(ValueDecoder.characteristic(vendor, [0x01, 0x02]), isNull);
    });
  });

  group('descriptors', () {
    test('Client Characteristic Configuration', () {
      expect(descriptor(0x2902, [0x00, 0x00]), 'Off');
      expect(descriptor(0x2902, [0x01, 0x00]), 'Notifications on');
      expect(descriptor(0x2902, [0x02, 0x00]), 'Indications on');
    });

    test('Characteristic User Description', () {
      expect(descriptor(0x2901, utf8.encode('Pulse')), '“Pulse”');
    });

    test('Characteristic Presentation Format', () {
      expect(
        descriptor(0x2904, [0x04, 0x00, 0xad, 0x27, 0x01, 0x00, 0x00]),
        'uint8 · percent',
      );
      expect(
        descriptor(0x2904, [0x0e, 0xfe, 0x2f, 0x27, 0x01, 0x00, 0x00]),
        'sint16 · °C · ×10^-2',
      );
    });

    test('Extended Properties and Report Reference', () {
      expect(descriptor(0x2900, [0x01, 0x00]), 'Reliable write');
      expect(descriptor(0x2900, [0x00, 0x00]), 'None');
      expect(descriptor(0x2908, [0x02, 0x01]), 'Report 2 · input');
    });
  });
}
