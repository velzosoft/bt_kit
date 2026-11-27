import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import 'app_uuids.dart';

enum DeviceKind {
  phone('Phone', 'phone', 'phones'),
  computer('Computer', 'computer', 'computers'),
  audio('Audio', 'audio device', 'audio'),
  wearable('Wearable', 'wearable', 'wearables'),
  health('Health & fitness', 'health device', 'health & fitness'),
  tracker('Tracker', 'tracker', 'trackers'),
  beacon('Beacon', 'beacon', 'beacons'),
  input('Input', 'input device', 'input'),
  media('TV & media', 'TV or media device', 'TV & media'),
  home('Smart home', 'smart home device', 'smart home'),
  unknown('Unknown', 'device', 'unknown');

  const DeviceKind(this.label, this.noun, this.plural);

  final String label;

  /// One device of this kind in a sentence, such as "Unnamed beacon".
  final String noun;
  final String plural;

  /// Such as "1 beacon" or "61 phones".
  String count(int n) => '$n ${n == 1 ? noun : plural}';
}

/// What a device was classified as, and which rule decided it.
final class DeviceCategory {
  const DeviceCategory(this.kind, this.reason);

  static const unknown = DeviceCategory(DeviceKind.unknown, 'No known marker');

  final DeviceKind kind;

  /// Such as "Heart Rate service" or "Apple · AirPods".
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is DeviceCategory && other.kind == kind && other.reason == reason;

  @override
  int get hashCode => Object.hash(kind, reason);
}

/// Classifies devices from their advertisement. Rules are checked in order:
/// advertised services, manufacturer company ID, GAP appearance.
///
/// Service UUIDs, company IDs and appearance categories come from the
/// Bluetooth SIG Assigned Numbers. Apple's message types are not SIG
/// numbers; they come from public Continuity protocol research.
abstract final class DeviceClassifier {
  static DeviceCategory classify(AdvertisementData data) =>
      _byService(data) ??
      _byCompany(data.manufacturerData) ??
      _byAppearance(data.appearance) ??
      DeviceCategory.unknown;

  static DeviceCategory? _byService(AdvertisementData data) {
    final advertised = {...data.serviceUuids, ...data.serviceData.keys};
    for (final MapEntry(key: uuid, value: category) in _services.entries) {
      if (advertised.contains(uuid)) return category;
    }
    return null;
  }

  static DeviceCategory? _byCompany(Map<int, Uint8List> manufacturerData) {
    for (final rule in _companies) {
      final data = manufacturerData[rule.company];
      if (data != null && rule.matches(data)) return rule.category;
    }
    return null;
  }

  static DeviceCategory? _byAppearance(int? appearance) {
    if (appearance == null) return null;
    final kind = _appearanceCategories[appearance >> 6];
    return kind == null ? null : DeviceCategory(kind, 'GAP appearance');
  }

  static final _services = <BluetoothUuid, DeviceCategory>{
    AppUuids.beacon: const DeviceCategory(DeviceKind.beacon, 'BT Radar beacon'),
    AppUuids.party: const DeviceCategory(DeviceKind.phone, 'BT Radar party'),
    AppUuids.fileBeam: const DeviceCategory(DeviceKind.phone, 'File beam'),
    AppUuids.lab: const DeviceCategory(DeviceKind.beacon, 'Lab reference'),
    ..._sig({
      0x180d: (DeviceKind.health, 'Heart Rate service'),
      0x1816: (DeviceKind.health, 'Cycling Speed and Cadence service'),
      0x1818: (DeviceKind.health, 'Cycling Power service'),
      0x1814: (DeviceKind.health, 'Running Speed and Cadence service'),
      0x1826: (DeviceKind.health, 'Fitness Machine service'),
      0x1810: (DeviceKind.health, 'Blood Pressure service'),
      0x1808: (DeviceKind.health, 'Glucose service'),
      0x181d: (DeviceKind.health, 'Weight Scale service'),
      0x1822: (DeviceKind.health, 'Pulse Oximeter service'),
      0x1809: (DeviceKind.health, 'Health Thermometer service'),
      0x1812: (DeviceKind.input, 'Human Interface Device service'),
      0x184e: (DeviceKind.audio, 'LE Audio'),
      0x1850: (DeviceKind.audio, 'LE Audio'),
      0x1844: (DeviceKind.audio, 'Volume Control service'),
      0x184f: (DeviceKind.audio, 'Broadcast Audio'),
      0x1852: (DeviceKind.audio, 'Broadcast Audio'),
      0x1854: (DeviceKind.audio, 'Hearing Access service'),
      0x181a: (DeviceKind.home, 'Environmental Sensing service'),
      0x1827: (DeviceKind.home, 'Bluetooth Mesh'),
      0x1828: (DeviceKind.home, 'Bluetooth Mesh'),
      0xfe2c: (DeviceKind.audio, 'Google Fast Pair'),
      0xfeaa: (DeviceKind.beacon, 'Eddystone'),
      0xfe9a: (DeviceKind.beacon, 'Estimote'),
      0xfd6f: (DeviceKind.phone, 'Exposure Notification'),
      0xfd5a: (DeviceKind.tracker, 'Samsung SmartTag'),
      0xfd69: (DeviceKind.tracker, 'Samsung SmartThings Find'),
      0xfeed: (DeviceKind.tracker, 'Tile'),
      0xfeec: (DeviceKind.tracker, 'Tile'),
      0xfe03: (DeviceKind.home, 'Amazon'),
      0xfe07: (DeviceKind.audio, 'Sonos'),
      0xfebe: (DeviceKind.audio, 'Bose'),
      0xfe95: (DeviceKind.home, 'Xiaomi'),
      0xfe0f: (DeviceKind.home, 'Philips Hue'),
      0xfff6: (DeviceKind.home, 'Matter'),
    }),
  };

  static Map<BluetoothUuid, DeviceCategory> _sig(
    Map<int, (DeviceKind, String)> rules,
  ) => {
    for (final MapEntry(key: uuid, value: (kind, reason)) in rules.entries)
      BluetoothUuid.short(uuid): DeviceCategory(kind, reason),
  };

  static const _apple = 0x004c;

  /// More specific rules for the same company come first.
  static const _companies = [
    _CompanyRule(_apple, DeviceKind.beacon, 'Apple · iBeacon', [0x02, 0x15]),
    _CompanyRule(_apple, DeviceKind.audio, 'Apple · AirPods or Beats', [0x07]),
    _CompanyRule(_apple, DeviceKind.tracker, 'Apple · Find My', [0x12]),
    _CompanyRule(_apple, DeviceKind.media, 'Apple · AirPlay', [0x09]),
    _CompanyRule(_apple, DeviceKind.wearable, 'Apple · Watch', [0x0b]),
    _CompanyRule(_apple, DeviceKind.phone, 'Apple'),
    _CompanyRule(0x0006, DeviceKind.computer, 'Microsoft'),
    _CompanyRule(0x0002, DeviceKind.computer, 'Intel'),
    _CompanyRule(0x0075, DeviceKind.phone, 'Samsung'),
    _CompanyRule(0x00e0, DeviceKind.phone, 'Google'),
    _CompanyRule(0x018e, DeviceKind.phone, 'Google'),
    _CompanyRule(0x0087, DeviceKind.wearable, 'Garmin'),
    _CompanyRule(0x0157, DeviceKind.wearable, 'Zepp (Huami)'),
    _CompanyRule(0x006b, DeviceKind.health, 'Polar'),
    _CompanyRule(0x009e, DeviceKind.audio, 'Bose'),
    _CompanyRule(0x012d, DeviceKind.audio, 'Sony'),
    _CompanyRule(0x0057, DeviceKind.audio, 'Harman'),
    _CompanyRule(0x05a7, DeviceKind.audio, 'Sonos'),
    _CompanyRule(0x00c4, DeviceKind.media, 'LG Electronics'),
    _CompanyRule(0x01da, DeviceKind.input, 'Logitech'),
    _CompanyRule(0x0171, DeviceKind.home, 'Amazon'),
    _CompanyRule(0x0499, DeviceKind.home, 'Ruuvi'),
    _CompanyRule(0x0969, DeviceKind.home, 'SwitchBot'),
  ];

  /// Keyed by the appearance category, the top 10 bits of the value.
  static const _appearanceCategories = {
    0x001: DeviceKind.phone,
    0x002: DeviceKind.computer,
    0x003: DeviceKind.wearable,
    0x004: DeviceKind.home,
    0x005: DeviceKind.media,
    0x006: DeviceKind.input,
    0x007: DeviceKind.wearable,
    0x008: DeviceKind.tracker,
    0x009: DeviceKind.tracker,
    0x00a: DeviceKind.audio,
    0x00b: DeviceKind.input,
    0x00c: DeviceKind.health,
    0x00d: DeviceKind.health,
    0x00e: DeviceKind.health,
    0x00f: DeviceKind.input,
    0x010: DeviceKind.health,
    0x011: DeviceKind.health,
    0x012: DeviceKind.health,
    0x015: DeviceKind.home,
    0x016: DeviceKind.home,
    0x017: DeviceKind.home,
    0x018: DeviceKind.home,
    0x01f: DeviceKind.home,
    0x021: DeviceKind.audio,
    0x022: DeviceKind.audio,
    0x025: DeviceKind.audio,
    0x027: DeviceKind.media,
    0x028: DeviceKind.media,
    0x029: DeviceKind.audio,
    0x02a: DeviceKind.input,
    0x031: DeviceKind.health,
    0x032: DeviceKind.health,
    0x051: DeviceKind.health,
  };
}

final class _CompanyRule {
  const _CompanyRule(this.company, this.kind, this.reason, [this.prefix]);

  final int company;
  final DeviceKind kind;
  final String reason;
  final List<int>? prefix;

  DeviceCategory get category => DeviceCategory(kind, reason);

  bool matches(Uint8List data) {
    final prefix = this.prefix;
    if (prefix == null) return true;
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }
}
