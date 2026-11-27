import 'dart:convert';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/app_uuids.dart';
import 'package:bt_radar/features/hunt/party/target_fingerprint.dart';
import 'package:bt_radar/features/hunt/party/target_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fastPair = BluetoothUuid.short(0xfe2c);
  final heartRate = BluetoothUuid.short(0x180d);
  const samsung = 0x0075;

  AdvertisementData ad({
    String? name,
    int? company,
    List<BluetoothUuid> services = const [],
    String? beacon,
  }) => AdvertisementData(
    localName: name,
    serviceUuids: services,
    manufacturerData: {?company: Uint8List(2)},
    serviceData: {
      if (beacon != null)
        AppUuids.beacon: Uint8List.fromList(ascii.encode(beacon)),
    },
  );

  MatchConfidence score(
    TargetFingerprint target,
    AdvertisementData data, {
    String id = 'aa:bb:cc:dd:ee:ff',
    bool idsAreAddresses = true,
  }) => TargetMatcher.confidence(
    target,
    id: id,
    data: data,
    idsAreAddresses: idsAreAddresses,
  );

  group('fingerprint', () {
    test('takes what every phone can see, and the address on Android', () {
      final fingerprint = TargetFingerprint.of(
        id: 'aa:bb:cc:dd:ee:ff',
        data: AdvertisementData(
          localName: 'Galaxy Buds2',
          manufacturerData: {samsung: Uint8List(2)},
          serviceUuids: [heartRate],
          serviceData: {fastPair: Uint8List(1)},
        ),
        idsAreAddresses: true,
      );
      expect(fingerprint.address, 'AA:BB:CC:DD:EE:FF');
      expect(fingerprint.localName, 'Galaxy Buds2');
      expect(fingerprint.company, samsung);
      expect(fingerprint.services, [heartRate, fastPair]);
      expect(fingerprint.quality, FingerprintQuality.address);
    });

    test('has no address where ids are per-app UUIDs', () {
      final fingerprint = TargetFingerprint.of(
        id: '6F1C0D5E-0000-4000-8000-000000000000',
        data: ad(name: 'Watch'),
        idsAreAddresses: false,
      );
      expect(fingerprint.address, isNull);
      expect(fingerprint.quality, FingerprintQuality.name);
    });

    test('reads the code of a BT Radar beacon', () {
      final fingerprint = TargetFingerprint.of(
        id: 'x',
        data: ad(beacon: 'K7QD'),
        idsAreAddresses: false,
      );
      expect(fingerprint.beaconCode, 'K7QD');
      expect(fingerprint.quality, FingerprintQuality.beacon);
    });

    test('keeps at most three services', () {
      final fingerprint = TargetFingerprint.of(
        id: 'x',
        data: ad(
          services: [for (var i = 1; i <= 5; i++) BluetoothUuid.short(i)],
        ),
        idsAreAddresses: false,
      );
      expect(fingerprint.services, hasLength(TargetFingerprint.maxServices));
      expect(fingerprint.quality, FingerprintQuality.traits);
    });

    test('survives JSON and tolerates junk', () {
      final fingerprint = TargetFingerprint(
        address: 'AA:BB:CC:DD:EE:FF',
        localName: 'Buds',
        beaconCode: 'K7QD',
        company: samsung,
        services: [fastPair],
      );
      final decoded = TargetFingerprint.fromJson(
        jsonDecode(jsonEncode(fingerprint.toJson())) as Map<String, Object?>,
      );
      expect(decoded.address, fingerprint.address);
      expect(decoded.localName, 'Buds');
      expect(decoded.beaconCode, 'K7QD');
      expect(decoded.company, samsung);
      expect(decoded.services, [fastPair]);

      final junk = TargetFingerprint.fromJson({
        'name': 3,
        'company': 'x',
        'services': ['zz', 'fe2c'],
      });
      expect(junk.localName, isNull);
      expect(junk.company, isNull);
      expect(junk.services, [fastPair]);
      expect(const TargetFingerprint().quality, FingerprintQuality.nothing);
    });
  });

  group('confidence', () {
    test('a beacon code decides alone', () {
      const target = TargetFingerprint(beaconCode: 'K7QD');
      expect(score(target, ad(beacon: 'K7QD')), MatchConfidence.certain);
      expect(score(target, ad(beacon: 'ABCD')), MatchConfidence.none);
    });

    test('the address is certain, between Android phones only', () {
      const target = TargetFingerprint(address: 'AA:BB:CC:DD:EE:FF');
      expect(score(target, ad()), MatchConfidence.certain);
      expect(score(target, ad(), idsAreAddresses: false), MatchConfidence.none);
    });

    test('the name with the same manufacturer is strong', () {
      const target = TargetFingerprint(localName: 'Buds', company: samsung);
      final other = 'Another device';
      expect(
        score(
          target,
          ad(name: 'Buds', company: samsung),
          id: other,
        ),
        MatchConfidence.strong,
      );
      expect(
        score(target, ad(name: 'Buds', company: 0x004c), id: other),
        MatchConfidence.weak,
      );
      expect(
        score(
          target,
          ad(name: 'Watch', company: samsung),
          id: other,
        ),
        MatchConfidence.none,
      );
    });

    test('an unnamed device can match by manufacturer and services', () {
      final target = TargetFingerprint(
        localName: 'Buds',
        company: samsung,
        services: [fastPair],
      );
      expect(
        score(
          target,
          ad(company: samsung, services: [fastPair]),
          id: 'x',
        ),
        MatchConfidence.weak,
      );
      expect(
        score(target, ad(company: samsung), id: 'x'),
        MatchConfidence.none,
      );
    });

    test('an empty fingerprint matches nothing', () {
      expect(
        score(const TargetFingerprint(), ad(company: samsung), id: 'x'),
        MatchConfidence.none,
      );
    });
  });

  group('ranking', () {
    test('orders by confidence, then by signal, and drops non-matches', () {
      final ranked = TargetMatch.rank([
        const TargetMatch('weak near', MatchConfidence.weak, -40),
        const TargetMatch('strong far', MatchConfidence.strong, -90),
        const TargetMatch('none', MatchConfidence.none, -30),
        const TargetMatch('strong near', MatchConfidence.strong, -50),
      ]);
      expect(
        [for (final m in ranked) m.device],
        ['strong near', 'strong far', 'weak near'],
      );
      expect(TargetMatch.isAmbiguous(ranked), isTrue);
      expect(TargetMatch.isAmbiguous(ranked.skip(1).toList()), isFalse);
    });
  });
}
