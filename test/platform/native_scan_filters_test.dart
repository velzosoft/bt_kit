import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/platform/native_scan_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final heartRate = BluetoothUuid.short(0x180d);
  final battery = BluetoothUuid.short(0x180f);

  group('Android', () {
    test('scans unfiltered without filters', () {
      expect(androidNativeFilters(const ScanOptions()), isEmpty);
    });

    test('keeps every field but nameContains', () {
      final filter = AdvertisementFilter(
        service: heartRate,
        name: 'Polar H10',
        nameContains: 'Polar',
        manufacturerId: 0x006b,
        manufacturerData: [1],
        serviceData: battery,
        serviceDataValue: [0x64],
      );
      expect(androidNativeFilters(ScanOptions(filters: [filter])), [
        AdvertisementFilter(
          service: heartRate,
          name: 'Polar H10',
          manufacturerId: 0x006b,
          manufacturerData: [1],
          serviceData: battery,
          serviceDataValue: [0x64],
        ),
      ]);
    });

    test('scans unfiltered when one filter has nothing native', () {
      expect(
        androidNativeFilters(
          ScanOptions(
            services: [heartRate],
            filters: [const AdvertisementFilter(nameContains: 'Polar')],
          ),
        ),
        isEmpty,
      );
    });

    test('passes MAC addresses in upper case and leaves other ids to Dart', () {
      expect(
        androidNativeFilters(
          const ScanOptions(
            filters: [AdvertisementFilter(peripheralId: 'c4:7c:8d:6a:12:34')],
          ),
        ),
        [const AdvertisementFilter(peripheralId: 'C4:7C:8D:6A:12:34')],
      );
      expect(
        androidNativeFilters(
          const ScanOptions(
            filters: [
              AdvertisementFilter(
                peripheralId: '5A0F2E7C-8B61-4B5D-9C1F-3D2A1E0B9C8D',
              ),
            ],
          ),
        ),
        isEmpty,
      );
    });

    test('adds one filter per service', () {
      expect(
        androidNativeFilters(ScanOptions(services: [heartRate, battery])),
        [
          AdvertisementFilter(service: heartRate),
          AdvertisementFilter(service: battery),
        ],
      );
    });
  });

  group('iOS', () {
    test('scans for the union of services when every filter names one', () {
      expect(
        iosNativeServices(
          ScanOptions(
            services: [battery],
            filters: [
              AdvertisementFilter(service: heartRate, nameContains: 'Polar'),
              AdvertisementFilter(service: battery, manufacturerId: 1),
            ],
          ),
        ),
        unorderedEquals([heartRate, battery]),
      );
    });

    test('scans unfiltered when a filter names no service', () {
      expect(iosNativeServices(const ScanOptions()), isNull);
      expect(
        iosNativeServices(
          ScanOptions(
            services: [heartRate],
            filters: [const AdvertisementFilter(name: 'Polar H10')],
          ),
        ),
        isNull,
      );
    });
  });
}
