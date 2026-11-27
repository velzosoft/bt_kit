import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/bluetooth_uuid.dart';

/// The content of an advertisement, the same on both platforms.
@immutable
final class AdvertisementData {
  const AdvertisementData({
    this.localName,
    this.serviceUuids = const [],
    this.solicitedServiceUuids = const [],
    this.serviceData = const {},
    this.manufacturerData = const {},
    this.txPowerLevel,
    this.isConnectable,
    this.appearance,
    this.flags,
  });

  /// Parses the advertising data structures of a raw advertisement or scan
  /// response, as defined by the Core Specification Supplement, Part A.
  ///
  /// Malformed trailing structures are ignored, as Android and iOS do.
  factory AdvertisementData.parse(Uint8List bytes, {bool? isConnectable}) {
    String? localName;
    int? txPowerLevel;
    int? appearance;
    int? flags;
    final services = <BluetoothUuid>[];
    final solicited = <BluetoothUuid>[];
    final serviceData = <BluetoothUuid, Uint8List>{};
    final manufacturerData = <int, Uint8List>{};

    var offset = 0;
    while (offset < bytes.length) {
      final length = bytes[offset];
      if (length == 0 || offset + 1 + length > bytes.length) break;
      final type = bytes[offset + 1];
      final data = Uint8List.sublistView(
        bytes,
        offset + 2,
        offset + 1 + length,
      );
      offset += 1 + length;
      switch (type) {
        case 0x01 when data.isNotEmpty:
          flags = data[0];
        case 0x02 || 0x03:
          services.addAll(_uuids(data, 2));
        case 0x04 || 0x05:
          services.addAll(_uuids(data, 4));
        case 0x06 || 0x07:
          services.addAll(_uuids(data, 16));
        case 0x08 || 0x09:
          if (type == 0x09 || localName == null) {
            localName = String.fromCharCodes(data);
          }
        case 0x0a when data.isNotEmpty:
          txPowerLevel = data[0].toSigned(8);
        case 0x14:
          solicited.addAll(_uuids(data, 2));
        case 0x1f:
          solicited.addAll(_uuids(data, 4));
        case 0x15:
          solicited.addAll(_uuids(data, 16));
        case 0x16 when data.length >= 2:
          _addServiceData(serviceData, data, 2);
        case 0x20 when data.length >= 4:
          _addServiceData(serviceData, data, 4);
        case 0x21 when data.length >= 16:
          _addServiceData(serviceData, data, 16);
        case 0x19 when data.length >= 2:
          appearance = data[0] | data[1] << 8;
        case 0xff when data.length >= 2:
          manufacturerData[data[0] | data[1] << 8] = Uint8List.fromList(
            data.sublist(2),
          );
      }
    }
    return AdvertisementData(
      localName: localName,
      serviceUuids: services,
      solicitedServiceUuids: solicited,
      serviceData: serviceData,
      manufacturerData: manufacturerData,
      txPowerLevel: txPowerLevel,
      isConnectable: isConnectable,
      appearance: appearance,
      flags: flags,
    );
  }

  final String? localName;
  final List<BluetoothUuid> serviceUuids;
  final List<BluetoothUuid> solicitedServiceUuids;
  final Map<BluetoothUuid, Uint8List> serviceData;

  /// Keyed by Bluetooth SIG company identifier.
  final Map<int, Uint8List> manufacturerData;

  /// Advertised transmit power in dBm.
  final int? txPowerLevel;
  final bool? isConnectable;

  /// GAP appearance. Not reported on iOS.
  final int? appearance;

  /// AD flags. Not reported on iOS.
  final int? flags;

  static Iterable<BluetoothUuid> _uuids(Uint8List data, int size) sync* {
    for (var i = 0; i + size <= data.length; i += size) {
      yield BluetoothUuid.fromBytes(data.sublist(i, i + size));
    }
  }

  static void _addServiceData(
    Map<BluetoothUuid, Uint8List> into,
    Uint8List data,
    int uuidSize,
  ) {
    into[BluetoothUuid.fromBytes(data.sublist(0, uuidSize))] =
        Uint8List.fromList(data.sublist(uuidSize));
  }
}
