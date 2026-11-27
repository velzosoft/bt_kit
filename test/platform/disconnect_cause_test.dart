import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/platform/android/android_gatt_client.dart';
import 'package:bt_kit/src/platform/ios/ios_gatt_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android', () {
    DisconnectCause cause(
      int status, {
      BluetoothConnectionState from = BluetoothConnectionState.connected,
      bool adapterOn = true,
    }) => androidDisconnectCause(status, from: from, adapterOn: adapterOn);

    test('maps HCI reasons while connected', () {
      expect(cause(8), DisconnectCause.linkLoss);
      expect(cause(34), DisconnectCause.linkLoss);
      expect(cause(19), DisconnectCause.remote);
      expect(cause(62), DisconnectCause.failedToConnect);
      expect(cause(133), DisconnectCause.unknown);
      expect(cause(22), DisconnectCause.unknown);
    });

    test('uses the state the link was in', () {
      expect(
        cause(133, from: BluetoothConnectionState.connecting),
        DisconnectCause.failedToConnect,
      );
      expect(
        cause(22, from: BluetoothConnectionState.disconnecting),
        DisconnectCause.requested,
      );
    });

    test('reports Bluetooth turning off first', () {
      expect(cause(19, adapterOn: false), DisconnectCause.adapterOff);
    });
  });

  group('iOS', () {
    test('maps CBError codes while connected', () {
      DisconnectCause cause(int? code) =>
          iosDisconnectCause(code, from: BluetoothConnectionState.connected);
      expect(cause(6), DisconnectCause.linkLoss);
      expect(cause(7), DisconnectCause.remote);
      expect(cause(10), DisconnectCause.failedToConnect);
      expect(cause(14), DisconnectCause.unknown);
      expect(cause(null), DisconnectCause.unknown);
    });

    test('uses the state the link was in', () {
      expect(
        iosDisconnectCause(null, from: BluetoothConnectionState.disconnecting),
        DisconnectCause.requested,
      );
      expect(
        iosDisconnectCause(7, from: BluetoothConnectionState.connecting),
        DisconnectCause.failedToConnect,
      );
    });
  });
}
