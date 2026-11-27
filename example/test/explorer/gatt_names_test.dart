import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/explorer/gatt_names.dart';
import 'package:bt_radar/features/explorer/property_chips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names come from Assigned Numbers, then the explorer table', () {
    expect(GattNames.service(BluetoothUuid.short(0x180f)), 'Battery');
    expect(
      GattNames.service(
        BluetoothUuid.parse('6e400001-b5a3-f393-e0a9-e50e24dcca9e'),
      ),
      'Nordic UART',
    );
    expect(
      GattNames.characteristic(BluetoothUuid.short(0x2a1c)),
      'Temperature Measurement',
    );
    expect(
      GattNames.descriptor(BluetoothUuid.short(0x2908)),
      'Report Reference',
    );
  });

  test('unknown attributes say what they are', () {
    expect(GattNames.service(BluetoothUuid.short(0xabcd)), 'Unnamed service');
    expect(
      GattNames.characteristic(
        BluetoothUuid.parse('12345678-1234-5678-1234-56789abcdef0'),
      ),
      'Vendor-specific characteristic',
    );
  });

  test('uuid shows 16-bit numbers in hex and others in full', () {
    expect(GattNames.uuid(BluetoothUuid.short(0x180d)), '0x180D');
    const full = '12345678-1234-5678-1234-56789abcdef0';
    expect(GattNames.uuid(BluetoothUuid.parse(full)), full);
  });

  test('property labels', () {
    expect(
      PropertyChips.labels(
        const CharacteristicProperties.of(
          read: true,
          writeWithoutResponse: true,
          notify: true,
        ),
      ),
      ['Read', 'Write without response', 'Notify'],
    );
  });
}
