import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/bluetooth_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describes failures in plain sentences', () {
    expect(
      describeBluetoothError(
        BluetoothUnavailableException(AdapterState.poweredOff),
      ),
      'Bluetooth is off. Turn it on and try again.',
    );
    expect(
      describeBluetoothError(
        const UnsupportedFeatureException(
          'peripheralRole',
          'This device cannot advertise',
        ),
      ),
      'This device cannot advertise.',
    );
    expect(
      describeBluetoothError(
        const AdvertisingException('No advertising slot is free'),
      ),
      'Could not start advertising. No advertising slot is free.',
    );
    expect(
      describeBluetoothError(GattException(GattError.writeNotPermitted, 'x')),
      contains('writeNotPermitted'),
    );
  });

  test('explains missing permissions', () {
    expect(
      describeMissingPermissions({
        BluetoothPermission.advertise: PermissionStatus.granted,
      }),
      isNull,
    );
    expect(
      describeMissingPermissions({
        BluetoothPermission.advertise: PermissionStatus.denied,
      }),
      contains('system settings'),
    );
    expect(
      describeMissingPermissions({
        BluetoothPermission.advertise: PermissionStatus.notDeclared,
      }),
      contains('does not declare'),
    );
  });
}
