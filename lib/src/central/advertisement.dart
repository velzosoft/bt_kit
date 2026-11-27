import '../models/advertisement_data.dart';
import 'native_types.dart';
import 'peripheral.dart';

/// One advertisement received while scanning.
final class Advertisement {
  const Advertisement({
    required this.peripheral,
    required this.rssi,
    required this.data,
    required this.receivedAt,
    this._native,
  });

  final Peripheral peripheral;

  /// Received signal strength in dBm. iOS reports 127 when unavailable.
  final int rssi;
  final AdvertisementData data;
  final DateTime receivedAt;
  final AdvertisementHandle? _native;

  /// `ScanResult` on Android; the arguments of
  /// `centralManager:didDiscoverPeripheral:advertisementData:RSSI:` on iOS.
  /// Fake advertisements have none and throw [UnsupportedError].
  AdvertisementHandle get native =>
      _native ??
      (throw UnsupportedError('A fake advertisement has no native object'));

  @override
  String toString() =>
      'Advertisement(${peripheral.id}, ${data.localName ?? '-'}, $rssi dBm)';
}
