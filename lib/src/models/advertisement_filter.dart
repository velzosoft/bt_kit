import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../core/bluetooth_uuid.dart';
import 'advertisement_data.dart';

/// Conditions an advertisement must meet. Every field that is set must
/// match; a scan with several filters reports advertisements that match
/// any of them.
///
/// ```dart
/// AdvertisementFilter(manufacturerId: 0x0059, manufacturerData: [0x01])
/// ```
@immutable
final class AdvertisementFilter {
  const AdvertisementFilter({
    this.service,
    this.name,
    this.nameContains,
    this.peripheralId,
    this.manufacturerId,
    this.manufacturerData,
    this.manufacturerDataMask,
    this.serviceData,
    this.serviceDataValue,
    this.serviceDataMask,
  }) : assert(
         manufacturerData == null || manufacturerId != null,
         'manufacturerData needs a manufacturerId',
       ),
       assert(
         serviceDataValue == null || serviceData != null,
         'serviceDataValue needs a serviceData UUID',
       );

  /// A service UUID the advertisement lists.
  final BluetoothUuid? service;

  /// The exact advertised local name.
  final String? name;

  /// Text the advertised local name contains.
  ///
  /// Only checked in Dart. A filter with nothing else leaves the native
  /// scan unfiltered, which Android stops while the screen is off.
  final String? nameContains;

  /// `Peripheral.id`, compared without regard to case.
  final String? peripheralId;

  /// A Bluetooth SIG company identifier the advertisement carries
  /// manufacturer data for.
  final int? manufacturerId;

  /// Bytes the manufacturer data starts with, after the company identifier.
  final List<int>? manufacturerData;

  /// Which bits of [manufacturerData] must match; all of them by default.
  final List<int>? manufacturerDataMask;

  /// A service UUID the advertisement carries service data for.
  final BluetoothUuid? serviceData;

  /// Bytes the service data starts with.
  final List<int>? serviceDataValue;

  /// Which bits of [serviceDataValue] must match; all of them by default.
  final List<int>? serviceDataMask;

  bool matches(String peripheralId, AdvertisementData data) {
    if (service case final uuid? when !data.serviceUuids.contains(uuid)) {
      return false;
    }
    if (name case final name? when data.localName != name) return false;
    if (nameContains case final part?
        when !(data.localName?.contains(part) ?? false)) {
      return false;
    }
    if (this.peripheralId case final id?
        when id.toUpperCase() != peripheralId.toUpperCase()) {
      return false;
    }
    if (manufacturerId case final company?
        when !_startsWith(
          data.manufacturerData[company],
          manufacturerData,
          manufacturerDataMask,
        )) {
      return false;
    }
    if (serviceData case final uuid?
        when !_startsWith(
          data.serviceData[uuid],
          serviceDataValue,
          serviceDataMask,
        )) {
      return false;
    }
    return true;
  }

  static bool _startsWith(
    List<int>? value,
    List<int>? prefix,
    List<int>? mask,
  ) {
    if (value == null) return false;
    if (prefix == null) return true;
    if (value.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      final bits = mask != null && i < mask.length ? mask[i] : 0xff;
      if (value[i] & bits != prefix[i] & bits) return false;
    }
    return true;
  }

  static const _bytes = ListEquality<int>();

  @override
  bool operator ==(Object other) =>
      other is AdvertisementFilter &&
      other.service == service &&
      other.name == name &&
      other.nameContains == nameContains &&
      other.peripheralId == peripheralId &&
      other.manufacturerId == manufacturerId &&
      _bytes.equals(other.manufacturerData, manufacturerData) &&
      _bytes.equals(other.manufacturerDataMask, manufacturerDataMask) &&
      other.serviceData == serviceData &&
      _bytes.equals(other.serviceDataValue, serviceDataValue) &&
      _bytes.equals(other.serviceDataMask, serviceDataMask);

  @override
  int get hashCode => Object.hash(
    service,
    name,
    nameContains,
    peripheralId,
    manufacturerId,
    _bytes.hash(manufacturerData),
    _bytes.hash(manufacturerDataMask),
    serviceData,
    _bytes.hash(serviceDataValue),
    _bytes.hash(serviceDataMask),
  );

  @override
  String toString() {
    final fields = {
      'service': service,
      'name': name,
      'nameContains': nameContains,
      'peripheralId': peripheralId,
      'manufacturerId': manufacturerId,
      'manufacturerData': manufacturerData,
      'manufacturerDataMask': manufacturerDataMask,
      'serviceData': serviceData,
      'serviceDataValue': serviceDataValue,
      'serviceDataMask': serviceDataMask,
    };
    return 'AdvertisementFilter(${[for (final MapEntry(:key, :value) in fields.entries)
      if (value != null) '$key: $value'].join(', ')})';
  }
}
