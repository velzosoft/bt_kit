import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/app_uuids.dart';
import 'package:bt_radar/bluetooth/device_kind.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceCategory classify({
  List<BluetoothUuid> services = const [],
  Map<BluetoothUuid, List<int>> serviceData = const {},
  Map<int, List<int>> manufacturer = const {},
  int? appearance,
}) => DeviceClassifier.classify(
  AdvertisementData(
    serviceUuids: services,
    serviceData: serviceData.map((k, v) => MapEntry(k, Uint8List.fromList(v))),
    manufacturerData: manufacturer.map(
      (k, v) => MapEntry(k, Uint8List.fromList(v)),
    ),
    appearance: appearance,
  ),
);

void main() {
  final heartRate = BluetoothUuid.short(0x180d);
  final fastPair = BluetoothUuid.short(0xfe2c);

  test('an advertised service decides first', () {
    final category = classify(
      services: [heartRate],
      manufacturer: {
        0x004c: [0x10],
      },
      appearance: 0x0040,
    );
    expect(category.kind, DeviceKind.health);
    expect(category.reason, 'Heart Rate service');
  });

  test('service data keys count as advertised services', () {
    expect(
      classify(
        serviceData: {
          fastPair: [1, 2, 3],
        },
      ).kind,
      DeviceKind.audio,
    );
  });

  test('the app recognizes its own beacon', () {
    expect(classify(services: [AppUuids.beacon]).kind, DeviceKind.beacon);
  });

  group('company IDs', () {
    test('Apple message types pick a specific kind', () {
      expect(
        classify(
          manufacturer: {
            0x004c: [0x02, 0x15, 0, 0],
          },
        ).kind,
        DeviceKind.beacon,
      );
      expect(
        classify(
          manufacturer: {
            0x004c: [0x07, 0x19],
          },
        ).kind,
        DeviceKind.audio,
      );
      expect(
        classify(
          manufacturer: {
            0x004c: [0x12, 0x02],
          },
        ).kind,
        DeviceKind.tracker,
      );
    });

    test('other Apple payloads fall back to the company rule', () {
      final category = classify(
        manufacturer: {
          0x004c: [0x10, 0x05],
        },
      );
      expect(category.kind, DeviceKind.phone);
      expect(category.reason, 'Apple');
    });

    test('a prefix longer than the data does not match', () {
      expect(
        classify(
          manufacturer: {
            0x004c: [0x02],
          },
        ).reason,
        'Apple',
      );
    });

    test('maps computer and phone makers', () {
      expect(classify(manufacturer: {0x0006: []}).kind, DeviceKind.computer);
      expect(classify(manufacturer: {0x0075: []}).kind, DeviceKind.phone);
      expect(classify(manufacturer: {0x00e0: []}).kind, DeviceKind.phone);
    });
  });

  test('GAP appearance comes after services and companies', () {
    expect(classify(appearance: 0x00c1).kind, DeviceKind.wearable);
    expect(classify(appearance: 0x0941).kind, DeviceKind.audio);
    expect(
      classify(manufacturer: {0x0006: []}, appearance: 0x00c1).kind,
      DeviceKind.computer,
    );
  });

  test('anything else is unknown', () {
    expect(classify(), DeviceCategory.unknown);
    expect(
      classify(
        manufacturer: {
          0xffff: [1],
        },
      ),
      DeviceCategory.unknown,
    );
    expect(classify(appearance: 0xffc0), DeviceCategory.unknown);
  });
}
