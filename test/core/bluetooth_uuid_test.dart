import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const heartRate = '0000180d-0000-1000-8000-00805f9b34fb';

  test('expands 16- and 32-bit forms onto the base UUID', () {
    expect(BluetoothUuid.parse('180D').value, heartRate);
    expect(BluetoothUuid.parse('0000180d').value, heartRate);
    expect(BluetoothUuid.short(0x180d).value, heartRate);
  });

  test('accepts 128-bit UUIDs with or without dashes', () {
    final dashed = BluetoothUuid.parse('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
    final plain = BluetoothUuid.parse('6e400001b5a3f393e0a9e50e24dcca9e');
    expect(dashed, plain);
    expect(dashed.shortValue, isNull);
    expect(dashed.toString(), '6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  });

  test('reads little-endian bytes as sent over the air', () {
    expect(BluetoothUuid.fromBytes([0x0d, 0x18]).value, heartRate);
  });

  test('prints the shortest standard form', () {
    expect(BluetoothUuid.parse(heartRate).toString(), '180d');
    expect(BluetoothUuid.short(0x1fffe).toString(), '0001fffe');
  });

  test('rejects malformed input', () {
    expect(() => BluetoothUuid.parse('18'), throwsFormatException);
    expect(() => BluetoothUuid.parse('zz0d'), throwsFormatException);
    expect(() => BluetoothUuid.fromBytes([1, 2, 3]), throwsFormatException);
  });
}
