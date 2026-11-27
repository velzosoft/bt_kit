import 'package:bt_kit/bt_kit.dart';

import '../../../bluetooth/beacon_code.dart';
import 'short_text.dart';

enum FingerprintQuality {
  /// A BT Radar beacon code: every phone recognizes it.
  beacon,

  /// A MAC address: other Android phones recognize it, iPhones cannot.
  address,

  /// An advertised name.
  name,

  /// Only the manufacturer and services, which similar devices share.
  traits,

  nothing,
}

/// What the hider's phone knows about the target, so that seekers' phones
/// can find the same device.
///
/// Device ids differ between phones: Android uses the MAC address, iOS a
/// UUID it makes up for each app. So the fingerprint carries what every
/// phone sees in the advertisement as well.
final class TargetFingerprint {
  const TargetFingerprint({
    this.address,
    this.localName,
    this.beaconCode,
    this.company,
    this.services = const [],
  });

  factory TargetFingerprint.of({
    required String id,
    required AdvertisementData data,
    required bool idsAreAddresses,
  }) {
    final name = data.localName;
    return TargetFingerprint(
      address: idsAreAddresses ? id.toUpperCase() : null,
      localName: name == null ? null : shortText(name, maxNameBytes),
      beaconCode: BeaconCode.read(data),
      company: data.manufacturerData.keys.firstOrNull,
      services: {
        ...data.serviceUuids,
        ...data.serviceData.keys,
      }.take(maxServices).toList(),
    );
  }

  factory TargetFingerprint.fromJson(Map<String, Object?> json) {
    final services = json['services'];
    return TargetFingerprint(
      address: _string(json['address']),
      localName: _string(json['name']),
      beaconCode: _string(json['beacon']),
      company: switch (json['company']) {
        final int company => company,
        _ => null,
      },
      services: [
        if (services is List<Object?>)
          for (final uuid in services.whereType<String>()) ?_uuid(uuid),
      ],
    );
  }

  /// No advertised name is longer.
  static const maxNameBytes = 29;
  static const maxServices = 3;

  final String? address;
  final String? localName;
  final String? beaconCode;
  final int? company;
  final List<BluetoothUuid> services;

  FingerprintQuality get quality => switch (this) {
    TargetFingerprint(beaconCode: _?) => FingerprintQuality.beacon,
    TargetFingerprint(address: _?) => FingerprintQuality.address,
    TargetFingerprint(localName: _?) => FingerprintQuality.name,
    TargetFingerprint(company: _?) => FingerprintQuality.traits,
    _ when services.isNotEmpty => FingerprintQuality.traits,
    _ => FingerprintQuality.nothing,
  };

  Map<String, Object?> toJson() => {
    'address': ?address,
    'name': ?localName,
    'beacon': ?beaconCode,
    'company': ?company,
    if (services.isNotEmpty) 'services': [for (final s in services) '$s'],
  };

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static BluetoothUuid? _uuid(String value) {
    try {
      return BluetoothUuid.parse(value);
    } on FormatException {
      return null;
    }
  }
}
