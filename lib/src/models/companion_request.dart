import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/bluetooth_uuid.dart';

/// What the system companion device picker offers, and how it presents it.
///
/// Name a [service] or a [manufacturerId]: AccessorySetupKit needs one of
/// them, and the app lists it in its `Info.plist`
/// (`NSAccessorySetupBluetoothServices` or
/// `NSAccessorySetupBluetoothCompanyIdentifiers`).
@immutable
final class CompanionRequest {
  const CompanionRequest({
    required this.displayName,
    this.productImage,
    this.service,
    this.nameContains,
    this.manufacturerId,
    this.manufacturerData,
    this.manufacturerDataMask,
    this.address,
    this.singleDevice = false,
  });

  /// iOS: the product name the picker shows. Android shows each device's
  /// own name.
  final String displayName;

  /// iOS: a PNG or JPEG of the product for the picker; a generic symbol
  /// when null. Android shows no image.
  final Uint8List? productImage;

  /// Devices that advertise this service.
  final BluetoothUuid? service;

  /// Devices whose name contains this text.
  final String? nameContains;

  /// Devices whose manufacturer data carries this company identifier.
  final int? manufacturerId;

  /// The manufacturer data that must follow [manufacturerId], compared
  /// under [manufacturerDataMask].
  final List<int>? manufacturerData;
  final List<int>? manufacturerDataMask;

  /// Android: the one device with this MAC address.
  final String? address;

  /// Android: when only one device matches, ask the user to confirm it
  /// instead of showing a list.
  final bool singleDevice;
}

/// How a companion device changed outside the app's own calls.
enum CompanionChangeKind { added, removed, changed }
