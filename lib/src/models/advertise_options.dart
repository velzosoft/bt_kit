import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/bluetooth_uuid.dart';

/// Trade-off between discovery latency and power use. Android only; iOS
/// chooses the interval itself.
enum AdvertiseMode { lowPower, balanced, lowLatency }

/// Transmit power. Android only.
enum AdvertiseTxPower { ultraLow, low, medium, high }

/// What to advertise.
///
/// Platforms differ in what they allow; check `BtKit.capabilities` first:
/// * iOS advertises only [localName] and [serviceUuids], always connectable,
///   and only while the app is in the foreground.
/// * Android cannot advertise a custom name, only the device name
///   ([includeDeviceName]).
@immutable
final class AdvertiseOptions {
  const AdvertiseOptions({
    this.localName,
    this.includeDeviceName = false,
    this.serviceUuids = const [],
    this.serviceData = const {},
    this.manufacturerData = const {},
    this.includeTxPower = false,
    this.connectable = true,
    this.extended = false,
    this.mode = AdvertiseMode.balanced,
    this.txPower = AdvertiseTxPower.medium,
    this.periodic,
  });

  /// iOS only. Requires `BluetoothCapabilities.advertiseLocalName`.
  final String? localName;

  /// Android only: advertises the system Bluetooth name.
  final bool includeDeviceName;

  final List<BluetoothUuid> serviceUuids;

  /// Requires `BluetoothCapabilities.advertiseCustomData`.
  final Map<BluetoothUuid, Uint8List> serviceData;

  /// Keyed by Bluetooth SIG company identifier. Requires
  /// `BluetoothCapabilities.advertiseCustomData`.
  final Map<int, Uint8List> manufacturerData;

  /// Requires `BluetoothCapabilities.advertiseCustomData`.
  final bool includeTxPower;

  final bool connectable;

  /// Bluetooth 5 extended advertising, which allows larger payloads but is
  /// invisible to legacy scanners. Requires
  /// `BluetoothCapabilities.extendedAdvertising`.
  final bool extended;

  final AdvertiseMode mode;
  final AdvertiseTxPower txPower;

  /// Periodic advertising alongside this advertisement, which must then be
  /// [extended] and not [connectable]. Requires
  /// `BluetoothCapabilities.periodicAdvertising`.
  final PeriodicAdvertising? periodic;
}

/// Data broadcast at a fixed interval, which receivers synchronize to
/// (Android).
///
/// Phones cannot synchronize to periodic advertising through public APIs;
/// receivers are usually embedded devices.
@immutable
final class PeriodicAdvertising {
  const PeriodicAdvertising({
    this.interval = const Duration(seconds: 1),
    this.serviceUuids = const [],
    this.serviceData = const {},
    this.manufacturerData = const {},
    this.includeTxPower = false,
  });

  /// From [minInterval] to [maxInterval], in steps of 1.25 ms.
  final Duration interval;

  final List<BluetoothUuid> serviceUuids;
  final Map<BluetoothUuid, Uint8List> serviceData;

  /// Keyed by Bluetooth SIG company identifier.
  final Map<int, Uint8List> manufacturerData;

  final bool includeTxPower;

  static const minInterval = Duration(milliseconds: 100);
  static const maxInterval = Duration(microseconds: 81898750);
}
