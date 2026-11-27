import 'package:bt_kit/bt_kit.dart';

import 'beacon_code.dart';
import 'device_kind.dart';
import 'rssi_filter.dart';
import 'signal.dart';

/// Everything the app knows about one nearby device, updated in place by
/// every advertisement it sends.
final class TrackedDevice {
  TrackedDevice(Advertisement first)
    : peripheral = first.peripheral,
      firstSeen = first.receivedAt,
      lastSeen = first.receivedAt,
      data = first.data,
      category = DeviceClassifier.classify(first.data) {
    _filter.add(first.rssi);
  }

  static const fadeAfter = Duration(seconds: 10);
  static const forgetAfter = Duration(seconds: 30);

  final Peripheral peripheral;
  final DateTime firstSeen;
  final _filter = RssiFilter();
  DateTime lastSeen;
  AdvertisementData data;
  DeviceCategory category;
  int advertisements = 1;

  late final String? _systemName = peripheral.name;

  String get id => peripheral.id;

  DeviceKind get kind => category.kind;

  /// The advertised name, or the name the system remembers. Android
  /// beacons cannot advertise a name, so theirs comes from the beacon code.
  String? get name => data.localName ?? _beaconName ?? _systemName;

  String? get _beaconName => switch (BeaconCode.read(data)) {
    final code? => BeaconCode.localName(code),
    null => null,
  };

  String get displayName => name ?? 'Unnamed ${kind.noun}';

  /// Smoothed signal strength in dBm.
  double get rssi => _filter.value ?? Signal.weakest;

  Proximity get proximity => Signal.proximity(rssi);

  Duration silenceAt(DateTime now) => now.difference(lastSeen);

  /// 1 while the device is heard, fading towards 0.2 between
  /// [fadeAfter] and [forgetAfter] of silence.
  double opacityAt(DateTime now) {
    final silence = silenceAt(now) - fadeAfter;
    if (silence <= Duration.zero) return 1;
    final span = forgetAfter - fadeAfter;
    return 1 - 0.8 * (silence.inMilliseconds / span.inMilliseconds).clamp(0, 1);
  }

  void update(Advertisement advertisement) {
    lastSeen = advertisement.receivedAt;
    advertisements++;
    _filter.add(advertisement.rssi);
    data = _merge(data, advertisement.data);
    category = DeviceClassifier.classify(data);
  }

  /// Advertisements and scan responses carry different fields, so keep what
  /// earlier packets said unless a newer one replaces it.
  static AdvertisementData _merge(
    AdvertisementData old,
    AdvertisementData next,
  ) => AdvertisementData(
    localName: next.localName ?? old.localName,
    serviceUuids: next.serviceUuids.isEmpty
        ? old.serviceUuids
        : {...old.serviceUuids, ...next.serviceUuids}.toList(),
    solicitedServiceUuids: next.solicitedServiceUuids.isEmpty
        ? old.solicitedServiceUuids
        : next.solicitedServiceUuids,
    serviceData: next.serviceData.isEmpty
        ? old.serviceData
        : {...old.serviceData, ...next.serviceData},
    manufacturerData: next.manufacturerData.isEmpty
        ? old.manufacturerData
        : next.manufacturerData,
    txPowerLevel: next.txPowerLevel ?? old.txPowerLevel,
    isConnectable: next.isConnectable ?? old.isConnectable,
    appearance: next.appearance ?? old.appearance,
    flags: next.flags ?? old.flags,
  );
}
