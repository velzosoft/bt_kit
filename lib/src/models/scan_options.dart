import 'package:meta/meta.dart';

import '../core/bluetooth_uuid.dart';
import 'advertisement_data.dart';
import 'advertisement_filter.dart';

/// Trade-off between discovery latency and power use.
enum ScanMode { lowPower, balanced, lowLatency }

/// The PHYs a scan listens on.
enum ScanPhy {
  /// Every PHY the adapter supports.
  all,
  le1M,

  /// Long range. Check `BluetoothCapabilities.leCodedPhy`.
  leCoded,
}

/// How to scan for advertising peripherals.
@immutable
final class ScanOptions {
  const ScanOptions({
    this.services = const [],
    this.filters = const [],
    this.mode = ScanMode.balanced,
    this.allowDuplicates = false,
    this.timeout,
    this.legacyOnly = false,
    this.phy = ScanPhy.all,
  }) : assert(
         !legacyOnly || phy != ScanPhy.leCoded,
         'Legacy advertisements are sent on LE 1M only',
       );

  /// Shorthand for one [AdvertisementFilter] per service.
  ///
  /// iOS does not deliver results for an unfiltered scan while the app is in
  /// the background, and Android stops unfiltered scans when the screen
  /// turns off.
  final List<BluetoothUuid> services;

  /// Report advertisements that match any of these filters, or every
  /// advertisement when there are none (and no [services]).
  ///
  /// Android checks the filters in the controller where it can. iOS can
  /// only filter natively when every filter names an
  /// [AdvertisementFilter.service];
  /// otherwise it scans unfiltered, which stops in the background, and the
  /// filters are checked in Dart.
  final List<AdvertisementFilter> filters;

  /// Ignored on iOS, which chooses its own duty cycle.
  final ScanMode mode;

  /// Report every advertisement instead of one per peripheral.
  final bool allowDuplicates;

  /// Stops the scan after this long.
  final Duration? timeout;

  /// Reports only legacy advertisements, leaving out Bluetooth 5 extended
  /// ones (Android). iOS ignores it.
  final bool legacyOnly;

  /// The PHYs to listen on (Android). iOS ignores it and listens on the
  /// PHYs it supports.
  final ScanPhy phy;

  /// [filters] and [services] together.
  List<AdvertisementFilter> get allFilters => [
    ...filters,
    for (final service in services) AdvertisementFilter(service: service),
  ];

  bool get isFiltered => filters.isNotEmpty || services.isNotEmpty;

  /// Whether an advertisement passes [filters] and [services].
  bool matches(String peripheralId, AdvertisementData data) =>
      !isFiltered ||
      services.any(data.serviceUuids.contains) ||
      filters.any((filter) => filter.matches(peripheralId, data));

  @override
  bool operator ==(Object other) =>
      other is ScanOptions &&
      other.mode == mode &&
      other.allowDuplicates == allowDuplicates &&
      other.timeout == timeout &&
      other.legacyOnly == legacyOnly &&
      other.phy == phy &&
      _sameItems(other.services, services) &&
      _sameItems(other.filters, filters);

  static bool _sameItems<T>(List<T> a, List<T> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  @override
  int get hashCode => Object.hash(
    mode,
    allowDuplicates,
    timeout,
    legacyOnly,
    phy,
    Object.hashAllUnordered(services),
    Object.hashAllUnordered(filters),
  );

  @override
  String toString() {
    final fields = [
      'mode: ${mode.name}',
      if (allowDuplicates) 'allowDuplicates',
      if (timeout != null) 'timeout: $timeout',
      if (legacyOnly) 'legacyOnly',
      if (phy != ScanPhy.all) 'phy: ${phy.name}',
      if (services.isNotEmpty) 'services: $services',
      if (filters.isNotEmpty) 'filters: $filters',
    ];
    return 'ScanOptions(${fields.join(', ')})';
  }
}
