import 'dart:async';
import 'dart:io';

import 'package:bt_kit/android.dart' as android;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bluetooth_setup.dart';

/// Android Layer 1 on its own: the manager and adapter, every callback
/// class implemented once, and an API newer than the device.
void androidSmokeTests() {
  group(
    'Android Layer 1',
    skip: Platform.isAndroid ? false : 'Android only',
    () {
      late android.Context context;
      late android.BluetoothManager manager;
      late android.BluetoothAdapter adapter;

      setUpAll(() async {
        await prepareBluetooth();
        context = android.androidApplicationContext.as(android.Context.type);
        manager = context
            .getSystemService$1(android.Context.BLUETOOTH_SERVICE!)!
            .as(android.BluetoothManager.type);
        adapter = manager.adapter!;
      });

      test('BluetoothManager reaches the adapter and its state', () {
        expect(adapter.state, android.BluetoothAdapter.STATE_ON);
      });

      test('ScanCallback scans without failing', () async {
        final failed = Completer<int>();
        var results = 0;
        final callback = android.ScanCallback.implement(
          onScanResult: (_, _) => results++,
          onScanFailed: (code) {
            if (!failed.isCompleted) failed.complete(code);
          },
        );
        expect(callback.isA(android.ScanCallback.type), isTrue);
        final scanner = adapter.bluetoothLeScanner!;
        scanner.startScan(callback);
        final code = await failed.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () => 0,
        );
        scanner.stopScan$1(callback);
        expect(code, 0, reason: 'onScanFailed($code)');
        debugPrint('ScanCallback: $results results in 4 s');
      });

      test('AdvertisingSetCallback reports start and stop', () async {
        final started = Completer<int>();
        final stopped = Completer<void>();
        final callback = android.AdvertisingSetCallback.implement(
          onAdvertisingSetStarted: (_, _, status) {
            if (!started.isCompleted) started.complete(status);
          },
          onAdvertisingSetStopped: (_) {
            if (!stopped.isCompleted) stopped.complete();
          },
        );
        final advertiser = adapter.bluetoothLeAdvertiser!;
        final parameters = android.AdvertisingSetParameters$Builder()
          ..setLegacyMode(true)
          ..setConnectable(false)
          ..setScannable(false)
          ..setInterval(android.AdvertisingSetParameters.INTERVAL_MEDIUM)
          ..setTxPowerLevel(android.AdvertisingSetParameters.TX_POWER_LOW);
        advertiser.startAdvertisingSet(
          parameters.build(),
          _smokeData(),
          null,
          null,
          null,
          callback,
        );
        expect(
          await waitFor(started.future, 'onAdvertisingSetStarted'),
          android.AdvertisingSetCallback.ADVERTISE_SUCCESS,
        );
        advertiser.stopAdvertisingSet(callback);
        await waitFor(stopped.future, 'onAdvertisingSetStopped');
      });

      test('AdvertiseCallback reports the start', () async {
        final outcome = Completer<String>();
        void settle(String value) {
          if (!outcome.isCompleted) outcome.complete(value);
        }

        final callback = android.AdvertiseCallback.implement(
          onStartSuccess: (_) => settle('started'),
          onStartFailure: (code) => settle('failed with $code'),
        );
        final settings = android.AdvertiseSettings$Builder()
          ..setConnectable(false)
          ..setAdvertiseMode(
            android.AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY,
          )
          ..setTimeout(0);
        final advertiser = adapter.bluetoothLeAdvertiser!;
        advertiser.startAdvertising(settings.build(), _smokeData(), callback);
        expect(await waitFor(outcome.future, 'AdvertiseCallback'), 'started');
        advertiser.stopAdvertising(callback);
      });

      test('BluetoothGattServerCallback reports the added service', () async {
        final added = Completer<int>();
        final callback = android.BluetoothGattServerCallback.implement(
          onServiceAdded: (status, _) {
            if (!added.isCompleted) added.complete(status);
          },
        );
        final server = manager.openGattServer(context, callback)!;
        try {
          final service = android.BluetoothGattService(
            android.UUID.fromString(smokeService.value.toJString()),
            android.BluetoothGattService.SERVICE_TYPE_PRIMARY,
          );
          expect(server.addService(service), isTrue);
          expect(
            await waitFor(added.future, 'onServiceAdded'),
            android.BluetoothGatt.GATT_SUCCESS,
          );
        } finally {
          server.close();
        }
      });

      test('BroadcastReceiver registers for adapter state changes', () {
        final receiver = android.BroadcastReceiver.implement(
          onReceive: (_, intent) => debugPrint('Adapter state: $intent'),
        );
        final filter = android.IntentFilter.new$2(
          android.BluetoothAdapter.ACTION_STATE_CHANGED,
        );
        context.registerReceiver$1(
          receiver,
          filter,
          android.Context.RECEIVER_NOT_EXPORTED,
        );
        context.unregisterReceiver(receiver);
      });

      test('the other callback classes can be implemented', () {
        final gatt = android.BluetoothGattCallback.implement(
          onConnectionStateChange: (_, _, _) {},
        );
        final hid = android.BluetoothHidDevice$Callback.implement(
          onAppStatusChanged: (_, _) {},
        );
        final companion = android.CompanionDeviceManager$Callback.implement(
          onFailure: (_, _) {},
        );
        android.CompanionDeviceService.implement(onDevicePresenceEvent: (_) {});
        expect(gatt.isA(android.BluetoothGattCallback.type), isTrue);
        expect(hid.isA(android.BluetoothHidDevice$Callback.type), isTrue);
        expect(
          companion.isA(android.CompanionDeviceManager$Callback.type),
          isTrue,
        );
      });

      test('BluetoothGattCallback connects to the reference', () async {
        final reference = await findReference();
        if (reference == null) {
          markTestSkipped('No Lab reference peripheral nearby');
          return;
        }
        final connected = Completer<int>();
        final discovered = Completer<int>();
        final callback = android.BluetoothGattCallback.implement(
          onConnectionStateChange: (_, status, state) {
            if (state == android.BluetoothProfile.STATE_CONNECTED &&
                !connected.isCompleted) {
              connected.complete(status);
            }
          },
          onServicesDiscovered: (_, status) {
            if (!discovered.isCompleted) discovered.complete(status);
          },
        );
        final device = adapter.getRemoteDevice$1(reference.id.toJString())!;
        // ignore: deprecated_member_use
        final gatt = device.connectGatt$3(
          context,
          false,
          callback,
          android.BluetoothDevice.TRANSPORT_LE,
          android.BluetoothDevice.PHY_LE_1M_MASK,
        )!;
        try {
          expect(
            await waitFor(connected.future, 'onConnectionStateChange'),
            android.BluetoothGatt.GATT_SUCCESS,
          );
          expect(gatt.discoverServices(), isTrue);
          expect(
            await waitFor(discovered.future, 'onServicesDiscovered'),
            android.BluetoothGatt.GATT_SUCCESS,
          );
          expect(gatt.services?.asDart(), isNotEmpty);
        } finally {
          gatt
            ..disconnect()
            ..close();
        }
      });

      test('an API newer than the device raises NoSuchMethodError', () {
        final device = adapter.getRemoteDevice$1(
          '00:11:22:33:44:55'.toJString(),
        )!;
        if (android.Build$VERSION.SDK_INT >= 35) {
          expect(device.addressType, isA<int>());
        } else {
          expect(
            () => device.addressType,
            throwsA(isA<android.NoSuchMethodError>()),
          );
        }
      });
    },
  );
}

android.AdvertiseData? _smokeData() =>
    (android.AdvertiseData$Builder()..addServiceUuid(
          android.ParcelUuid.fromString(smokeService.value.toJString()),
        ))
        .build();
