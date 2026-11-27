import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final heartRate = BluetoothUuid.short(0x180d);
  final battery = BluetoothUuid.short(0x180f);
  const id = 'C4:7C:8D:6A:12:34';
  final polar = AdvertisementData(
    localName: 'Polar H10 1234',
    serviceUuids: [heartRate],
    manufacturerData: {
      0x006b: Uint8List.fromList([0x01, 0x02, 0x03]),
    },
    serviceData: {
      battery: Uint8List.fromList([0x64]),
    },
  );

  group('one filter', () {
    test('matches when every field it sets matches', () {
      expect(
        AdvertisementFilter(
          service: heartRate,
          nameContains: 'Polar',
          manufacturerId: 0x006b,
        ).matches(id, polar),
        isTrue,
      );
      expect(
        AdvertisementFilter(
          service: heartRate,
          nameContains: 'Garmin',
        ).matches(id, polar),
        isFalse,
      );
    });

    test('compares names exactly or by substring', () {
      expect(
        const AdvertisementFilter(name: 'Polar H10 1234').matches(id, polar),
        isTrue,
      );
      expect(
        const AdvertisementFilter(name: 'Polar').matches(id, polar),
        isFalse,
      );
      expect(
        const AdvertisementFilter(nameContains: 'H10').matches(id, polar),
        isTrue,
      );
      expect(
        const AdvertisementFilter(nameContains: 'x')
            .matches(id, const AdvertisementData()),
        isFalse,
      );
    });

    test('compares peripheral ids without regard to case', () {
      expect(
        const AdvertisementFilter(peripheralId: 'c4:7c:8d:6a:12:34')
            .matches(id, polar),
        isTrue,
      );
      expect(
        const AdvertisementFilter(peripheralId: 'AA:BB:CC:DD:EE:FF')
            .matches(id, polar),
        isFalse,
      );
    });

    test('matches manufacturer data by prefix and mask', () {
      bool matches(List<int>? data, [List<int>? mask]) => AdvertisementFilter(
        manufacturerId: 0x006b,
        manufacturerData: data,
        manufacturerDataMask: mask,
      ).matches(id, polar);

      expect(matches(null), isTrue);
      expect(matches([0x01, 0x02]), isTrue);
      expect(matches([0x01, 0x09]), isFalse);
      expect(matches([0x01, 0x09], [0xff, 0x00]), isTrue);
      expect(matches([0x01, 0x02, 0x03, 0x04]), isFalse);
      expect(
        const AdvertisementFilter(manufacturerId: 0x0059).matches(id, polar),
        isFalse,
      );
    });

    test('matches service data by prefix and mask', () {
      expect(
        AdvertisementFilter(serviceData: battery).matches(id, polar),
        isTrue,
      );
      expect(
        AdvertisementFilter(
          serviceData: battery,
          serviceDataValue: [0x64],
        ).matches(id, polar),
        isTrue,
      );
      expect(
        AdvertisementFilter(
          serviceData: battery,
          serviceDataValue: [0x60],
          serviceDataMask: [0xf0],
        ).matches(id, polar),
        isTrue,
      );
      expect(
        AdvertisementFilter(serviceData: heartRate).matches(id, polar),
        isFalse,
      );
    });
  });

  group('scan options', () {
    test('pass an advertisement that matches any filter', () {
      final options = ScanOptions(
        filters: [
          const AdvertisementFilter(name: 'Garmin'),
          AdvertisementFilter(service: heartRate),
        ],
      );
      expect(options.matches(id, polar), isTrue);
      expect(
        options.matches(id, const AdvertisementData(localName: 'Fitbit')),
        isFalse,
      );
    });

    test('treat services as one filter each', () {
      expect(ScanOptions(services: [battery]).matches(id, polar), isFalse);
      expect(
        ScanOptions(services: [battery, heartRate]).matches(id, polar),
        isTrue,
      );
      expect(
        ScanOptions(
          services: [battery],
          filters: [const AdvertisementFilter(nameContains: 'Polar')],
        ).matches(id, polar),
        isTrue,
      );
    });

    test('pass everything without filters', () {
      expect(
        const ScanOptions().matches(id, const AdvertisementData()),
        isTrue,
      );
    });

    test('are equal regardless of filter order', () {
      final a = ScanOptions(
        filters: [
          AdvertisementFilter(manufacturerId: 1, manufacturerData: [1, 2]),
          const AdvertisementFilter(name: 'x'),
        ],
      );
      final b = ScanOptions(
        filters: [
          const AdvertisementFilter(name: 'x'),
          AdvertisementFilter(manufacturerId: 1, manufacturerData: [1, 2]),
        ],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          ScanOptions(
            filters: [
              AdvertisementFilter(manufacturerId: 1, manufacturerData: [1, 3]),
              const AdvertisementFilter(name: 'x'),
            ],
          ),
        ),
      );
    });
  });
}
