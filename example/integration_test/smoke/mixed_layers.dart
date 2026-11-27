import 'dart:async';

import 'package:bt_kit/android.dart' as android;
import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/ios.dart' as ios;
import 'package:bt_radar/bluetooth/scanner.dart';
import 'package:bt_radar/features/lab/central/lab_connection.dart';
import 'package:bt_radar/features/lab/profile/reference_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bluetooth_setup.dart';

/// Layer 1 objects reached through Layer 2's `native`, and Layer 1 calls
/// inside `Peripheral.exclusive`.
void mixedLayerTests() {
  group('Mixed layers', () {
    setUpAll(prepareBluetooth);

    test('BtKit.native is the platform adapter', () {
      switch (BtKit.instance.native) {
        case AndroidHandle(:final value):
          expect(value.state, android.BluetoothAdapter.STATE_ON);
        case IosHandle(:final value):
          expect(value.state, ios.CBManagerState.CBManagerStatePoweredOn);
      }
    });

    test('Advertisement.native is what the platform delivered', () async {
      final Advertisement ad;
      try {
        ad = await BtKit.instance
            .scan(Scanner.options)
            .first
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        markTestSkipped('No advertisement within 10 s');
        return;
      }
      switch (ad.native) {
        case AndroidHandle(:final value):
          expect(value.rssi, ad.rssi);
        case IosHandle(:final value):
          expect(value.rssi.intValue, ad.rssi);
      }
    });

    test('GattServer.native is the platform server', () async {
      final server = await BtKit.instance.openGattServer();
      try {
        switch (server.native) {
          case AndroidHandle(:final value):
            expect(value.services?.asDart(), isEmpty);
          case IosHandle(:final value):
            expect(value.state, ios.CBManagerState.CBManagerStatePoweredOn);
        }
      } finally {
        await server.close();
      }
    });

    test('Layer 1 calls inside Peripheral.exclusive', () async {
      final reference = await findReference();
      if (reference == null) {
        markTestSkipped('No Lab reference peripheral nearby');
        return;
      }
      final connection = await LabConnection.open(
        reference,
        timeout: const Duration(seconds: 10),
      );
      try {
        final peripheral = connection.peripheral;
        final usable = await peripheral.exclusive(
          () async => switch (peripheral.native) {
            AndroidHandle(:final value) =>
              value.gatt!.requestConnectionPriority(
                android.BluetoothGatt.CONNECTION_PRIORITY_BALANCED,
              ),
            IosHandle(:final value) =>
              value.state == ios.CBPeripheralState.CBPeripheralStateConnected,
          },
        );
        expect(usable, isTrue);

        final fixed = connection[ReferenceCharacteristic.fixedValue];
        switch (fixed.native) {
          case AndroidHandle(:final value):
            expect(
              value.properties &
                  android.BluetoothGattCharacteristic.PROPERTY_READ,
              isNonZero,
            );
          case IosHandle(:final value):
            expect(
              value.properties &
                  ios.CBCharacteristicProperties.CBCharacteristicPropertyRead,
              isNonZero,
            );
        }
        expect(await fixed.read(), ReferenceProfile.fixedValue);
      } finally {
        await connection.close();
      }
    });
  });
}
