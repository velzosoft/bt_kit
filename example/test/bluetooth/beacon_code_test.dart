import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/app_uuids.dart';
import 'package:bt_radar/bluetooth/beacon_code.dart';
import 'package:flutter_test/flutter_test.dart';

BluetoothCapabilities capabilities({
  required bool localName,
  required bool customData,
}) => BluetoothCapabilities(
  lowEnergy: true,
  classic: false,
  le2MPhy: false,
  leCodedPhy: false,
  extendedAdvertising: false,
  periodicAdvertising: false,
  channelSounding: false,
  requestMtu: false,
  connectionPriority: false,
  phy: false,
  notifyMode: false,
  requestEnable: false,
  peripheralRole: true,
  advertiseLocalName: localName,
  advertiseCustomData: customData,
  l2cap: false,
  bonding: false,
  removeBond: false,
  externalAccessory: false,
  companionDevices: false,
  backgroundEvents: false,
  stateRestoration: false,
  systemConnectionEvents: false,
  rssiRanging: false,
  audioProfiles: false,
  gattCacheRefresh: false,
  adapterName: false,
  serverConnectionPriority: false,
);

void main() {
  test('codes are 4 characters that are easy to read aloud', () {
    final random = Random(7);
    for (var i = 0; i < 200; i++) {
      final code = BeaconCode.generate(random);
      expect(code, hasLength(4));
      expect(BeaconCode.isValid(code), isTrue);
      expect(code, isNot(matches(RegExp('[01OI]'))));
    }
  });

  test('Android advertises the code as service data only', () {
    final options = BeaconCode.advertiseOptions(
      'K7QD',
      capabilities(localName: false, customData: true),
    );
    expect(options.localName, isNull);
    expect(options.serviceUuids, isEmpty);
    expect(options.serviceData[AppUuids.beacon], ascii.encode('K7QD'));
    expect(options.mode, AdvertiseMode.lowLatency);
    expect(options.txPower, AdvertiseTxPower.high);
  });

  test('the Android advertisement fits a legacy advertisement', () {
    const flags = 3;
    const serviceData = 2 + 16 + BeaconCode.length;
    expect(flags + serviceData, lessThanOrEqualTo(31));
  });

  test('iOS advertises the service and the code in the local name', () {
    final options = BeaconCode.advertiseOptions(
      'K7QD',
      capabilities(localName: true, customData: false),
    );
    expect(options.localName, 'Radar K7QD');
    expect(options.serviceUuids, [AppUuids.beacon]);
    expect(options.serviceData, isEmpty);
  });

  group('read', () {
    test('finds the code in service data', () {
      final data = AdvertisementData(
        serviceData: {
          AppUuids.beacon: Uint8List.fromList(ascii.encode('K7QD')),
        },
      );
      expect(BeaconCode.read(data), 'K7QD');
    });

    test('finds the code in the local name next to the service', () {
      final data = AdvertisementData(
        localName: 'Radar K7QD',
        serviceUuids: [AppUuids.beacon],
      );
      expect(BeaconCode.read(data), 'K7QD');
    });

    test('ignores the name without the beacon service', () {
      expect(
        BeaconCode.read(const AdvertisementData(localName: 'Radar K7QD')),
        isNull,
      );
    });

    test('ignores invalid codes', () {
      final data = AdvertisementData(
        localName: 'Radar 0000',
        serviceUuids: [AppUuids.beacon],
        serviceData: {
          AppUuids.lab: Uint8List.fromList([1, 2]),
        },
      );
      expect(BeaconCode.read(data), isNull);
      expect(
        BeaconCode.read(
          AdvertisementData(
            serviceData: {
              AppUuids.beacon: Uint8List.fromList([0xff]),
            },
          ),
        ),
        isNull,
      );
    });
  });
}
