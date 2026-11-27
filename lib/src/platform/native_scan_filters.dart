import '../core/bluetooth_uuid.dart';
import '../models/advertisement_filter.dart';
import '../models/scan_options.dart';

/// The part of each filter Android's native `ScanFilter` can check:
/// everything except [AdvertisementFilter.nameContains], and an
/// [AdvertisementFilter.peripheralId] only when it is a MAC address.
///
/// Filters are alternatives, so if any filter has nothing Android can
/// check, the native scan must run unfiltered and this returns an empty
/// list. Every result is checked in Dart afterwards either way.
List<AdvertisementFilter> androidNativeFilters(ScanOptions options) {
  final native = [for (final filter in options.allFilters) _android(filter)];
  return native.contains(const AdvertisementFilter()) ? const [] : native;
}

/// The services iOS can scan for natively, or null when some filter does
/// not name a service and the scan must run unfiltered.
List<BluetoothUuid>? iosNativeServices(ScanOptions options) {
  final filters = options.allFilters;
  if (filters.isEmpty || filters.any((f) => f.service == null)) return null;
  return {for (final filter in filters) filter.service!}.toList();
}

final _macAddress = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

AdvertisementFilter _android(AdvertisementFilter filter) {
  final address = filter.peripheralId?.toUpperCase();
  return AdvertisementFilter(
    service: filter.service,
    name: filter.name,
    peripheralId: address != null && _macAddress.hasMatch(address)
        ? address
        : null,
    manufacturerId: filter.manufacturerId,
    manufacturerData: filter.manufacturerData,
    manufacturerDataMask: filter.manufacturerDataMask,
    serviceData: filter.serviceData,
    serviceDataValue: filter.serviceDataValue,
    serviceDataMask: filter.serviceDataMask,
  );
}
