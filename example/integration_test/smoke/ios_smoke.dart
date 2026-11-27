import 'dart:async';
import 'dart:io';

import 'package:bt_kit/ios.dart' as ios;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bluetooth_setup.dart';

/// iOS Layer 1 on its own: both managers and their state, every delegate
/// implemented once, and an API newer than the OS.
void iosSmokeTests() {
  group('iOS Layer 1', skip: Platform.isIOS ? false : 'iOS only', () {
    setUpAll(prepareBluetooth);

    test('CBCentralManager reports its state to its delegate', () async {
      final central = await _central();
      expect(central.state, ios.CBManagerState.CBManagerStatePoweredOn);
      expect(
        ios.CBManager.getAuthorization(),
        ios.CBManagerAuthorization.CBManagerAuthorizationAllowedAlways,
      );
    });

    test('CBCentralManagerDelegate hears a scan', () async {
      var discovered = 0;
      final central = await _central(onDiscover: (_, _, _, _) => discovered++);
      central.scanForPeripheralsWithServices(null, options: null);
      await Future<void>.delayed(const Duration(seconds: 4));
      central.stopScan();
      debugPrint('CBCentralManagerDelegate: $discovered peripherals in 4 s');
    });

    test('CBPeripheralManager adds a service and advertises', () async {
      final state = Completer<ios.CBManagerState>();
      final added = Completer<ios.NSError?>();
      final advertising = Completer<ios.NSError?>();
      final delegate = ios.CBPeripheralManagerDelegate.implement(
        peripheralManagerDidUpdateState_: (manager) {
          if (!state.isCompleted) state.complete(manager.state);
        },
        peripheralManager_didAddService_error_: (_, _, error) {
          if (!added.isCompleted) added.complete(error);
        },
        peripheralManagerDidStartAdvertising_error_: (_, error) {
          if (!advertising.isCompleted) advertising.complete(error);
        },
      );
      keepAlive.add(delegate);
      final manager = ios.CBPeripheralManager.alloc().initWithDelegate(
        delegate,
        queue: null,
      );
      expect(
        await waitFor(state.future, 'peripheralManagerDidUpdateState'),
        ios.CBManagerState.CBManagerStatePoweredOn,
      );
      final uuid = ios.CBUUID.UUIDWithString(smokeService.value.toNSString());
      manager.addService(
        ios.CBMutableService.alloc().initWithType(uuid, primary: true),
      );
      expect(await waitFor(added.future, 'didAddService'), isNull);
      manager.startAdvertising(
        {ios.CBAdvertisementDataLocalNameKey: 'bt_kit smoke'}.toNSDictionary(),
      );
      expect(await waitFor(advertising.future, 'didStartAdvertising'), isNull);
      manager
        ..stopAdvertising()
        ..removeAllServices();
    });

    test('CBPeripheralDelegate discovers the reference', () async {
      final reference = await findReference();
      if (reference == null) {
        markTestSkipped('No Lab reference peripheral nearby');
        return;
      }
      final connected = Completer<void>();
      final central = await _central(
        onConnect: (_, _) {
          if (!connected.isCompleted) connected.complete();
        },
      );
      final identifier = ios.NSUUID.alloc().initWithUUIDString(
        reference.id.toNSString(),
      )!;
      final known = central
          .retrievePeripheralsWithIdentifiers(ios.NSArray.of([identifier]))
          .asDart();
      expect(known, isNotEmpty);
      final peripheral = ios.CBPeripheral.as(known.first);
      final discovered = Completer<ios.NSError?>();
      final delegate = ios.CBPeripheralDelegate.implement(
        peripheral_didDiscoverServices_: (_, error) {
          if (!discovered.isCompleted) discovered.complete(error);
        },
      );
      keepAlive.add(delegate);
      peripheral.delegate = delegate;
      central.connectPeripheral(peripheral, options: null);
      try {
        await waitFor(connected.future, 'didConnectPeripheral');
        peripheral.discoverServices(null);
        expect(await waitFor(discovered.future, 'didDiscoverServices'), isNull);
        expect(peripheral.services?.asDart(), isNotEmpty);
      } finally {
        central.cancelPeripheralConnection(peripheral);
      }
    });

    test('EAAccessoryDelegate can be implemented', () {
      keepAlive.add(
        ios.EAAccessoryDelegate.implement(accessoryDidDisconnect_: (_) {}),
      );
    });

    test('an API newer than the OS throws OsVersionError', () {
      final session = ios.ASAccessorySession();
      if (ios.osVersion.major >= 26) {
        expect(() => session.pickerDisplaySettings, returnsNormally);
      } else {
        expect(
          () => session.pickerDisplaySettings,
          throwsA(isA<ios.OsVersionError>()),
        );
      }
    });
  });
}

/// A new `CBCentralManager`, once its delegate reports it powered on.
Future<ios.CBCentralManager> _central({
  void Function(
    ios.CBCentralManager,
    ios.CBPeripheral,
    ios.NSDictionary,
    ios.NSNumber,
  )?
  onDiscover,
  void Function(ios.CBCentralManager, ios.CBPeripheral)? onConnect,
}) async {
  final state = Completer<ios.CBManagerState>();
  final delegate = ios.CBCentralManagerDelegate.implement(
    centralManagerDidUpdateState_: (central) {
      if (!state.isCompleted) state.complete(central.state);
    },
    centralManager_didDiscoverPeripheral_advertisementData_RSSI_: onDiscover,
    centralManager_didConnectPeripheral_: onConnect,
  );
  keepAlive.add(delegate);
  final central = ios.CBCentralManager.alloc().initWithDelegate(
    delegate,
    queue: null,
  );
  keepAlive.add(central);
  expect(
    await waitFor(state.future, 'centralManagerDidUpdateState'),
    ios.CBManagerState.CBManagerStatePoweredOn,
  );
  return central;
}
