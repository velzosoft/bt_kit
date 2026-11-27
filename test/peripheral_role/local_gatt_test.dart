import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CharacteristicProperties.of sets the specification bits', () {
    const properties = CharacteristicProperties.of(
      read: true,
      writeWithoutResponse: true,
      notify: true,
    );
    expect(properties.bits, 0x02 | 0x04 | 0x10);
    expect(properties.read && properties.notify, isTrue);
    expect(properties.indicate, isFalse);
  });

  test('permissions default to what the properties allow', () {
    final characteristic = LocalCharacteristic(
      BluetoothUuid.short(0x2a37),
      properties: const CharacteristicProperties.of(
        read: true,
        writeWithoutResponse: true,
      ),
    );
    expect(characteristic.permissions, {
      AttributePermission.read,
      AttributePermission.write,
    });
  });

  test('the CCCD is managed by bt_kit', () {
    expect(
      () => LocalCharacteristic(
        BluetoothUuid.short(0x2a37),
        properties: const CharacteristicProperties.of(notify: true),
        descriptors: [
          LocalDescriptor(BluetoothUuid.clientCharacteristicConfiguration),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('values are limited to 512 bytes', () {
    expect(
      () => LocalDescriptor(
        BluetoothUuid.short(0x2901),
        value: List.filled(513, 0),
      ),
      throwsArgumentError,
    );
  });

  test('user description descriptors carry UTF-8 text', () {
    final descriptor = LocalDescriptor.userDescription('Heart rate');
    expect(descriptor.uuid, BluetoothUuid.short(0x2901));
    expect(String.fromCharCodes(descriptor.value), 'Heart rate');
  });
}
