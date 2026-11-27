import 'dart:convert';
import 'dart:typed_data';

import 'package:objective_c/objective_c.dart' as objc;

import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../models/advertisement_data.dart';
import '../../native/ios/bindings.dart';

BluetoothUuid uuidOf(CBUUID uuid) =>
    BluetoothUuid.parse(uuid.UUIDString.toDartString());

CBUUID cbUuid(BluetoothUuid uuid) =>
    CBUUID.UUIDWithString(uuid.value.toNSString());

/// Identifies a CoreBluetooth object across callbacks, which hand back the
/// same instance each time.
int keyOf(objc.ObjCObject object) => object.ref.pointer.address;

List<T> listOf<T>(objc.NSArray? array, T Function(objc.ObjCObject) cast) => [
  for (final item in array?.asDart() ?? const <objc.ObjCObject>[]) cast(item),
];

/// The bytes of an attribute value. Descriptor values arrive as `NSData`,
/// `NSNumber` or `NSString` depending on the descriptor type.
Uint8List bytesOf(objc.ObjCObject? value) {
  if (value == null) return Uint8List(0);
  if (objc.NSData.isA(value)) return objc.NSData.as(value).toList();
  if (objc.NSString.isA(value)) {
    return utf8.encode(objc.NSString.as(value).toDartString());
  }
  if (objc.NSNumber.isA(value)) {
    final number = objc.NSNumber.as(value).longLongValue;
    return Uint8List(2)
      ..buffer.asByteData().setUint16(0, number, Endian.little);
  }
  return Uint8List(0);
}

BluetoothException errorOf(objc.NSError error, String operation) {
  final domain = error.domain.toDartString();
  if (domain == CBATTErrorDomain.toDartString()) {
    return GattException(
      GattError.fromCode(error.code),
      operation,
      nativeCode: error.code,
      nativeError: error,
    );
  }
  return NativeOperationException(
    '$operation failed: ${error.localizedDescription.toDartString()}',
    nativeCode: error.code,
    nativeError: error,
  );
}

/// Maps the dictionary CoreBluetooth passes to
/// `centralManager:didDiscoverPeripheral:advertisementData:RSSI:`.
AdvertisementData advertisementOf(objc.NSDictionary dictionary) {
  final data = dictionary.asDart();
  objc.ObjCObject? value(objc.NSString key) => data[key];
  List<BluetoothUuid> uuids(objc.NSString key) =>
      listOf(value(key) as objc.NSArray?, (o) => uuidOf(CBUUID.as(o)));

  final manufacturer = value(CBAdvertisementDataManufacturerDataKey);
  final manufacturerBytes = manufacturer == null
      ? null
      : objc.NSData.as(manufacturer).toList();
  final serviceData = value(CBAdvertisementDataServiceDataKey);
  final txPower = value(CBAdvertisementDataTxPowerLevelKey);
  final connectable = value(CBAdvertisementDataIsConnectable);
  final name = value(CBAdvertisementDataLocalNameKey);

  return AdvertisementData(
    localName: name == null ? null : objc.NSString.as(name).toDartString(),
    serviceUuids: [
      ...uuids(CBAdvertisementDataServiceUUIDsKey),
      ...uuids(CBAdvertisementDataOverflowServiceUUIDsKey),
    ],
    solicitedServiceUuids: uuids(CBAdvertisementDataSolicitedServiceUUIDsKey),
    serviceData: {
      if (serviceData != null)
        for (final MapEntry(:key, :value) in objc.NSDictionary.as(
          serviceData,
        ).asDart().entries)
          uuidOf(CBUUID.as(key)): objc.NSData.as(value).toList(),
    },
    manufacturerData: {
      if (manufacturerBytes != null && manufacturerBytes.length >= 2)
        manufacturerBytes[0] | manufacturerBytes[1] << 8: Uint8List.fromList(
          manufacturerBytes.sublist(2),
        ),
    },
    txPowerLevel: txPower == null ? null : objc.NSNumber.as(txPower).intValue,
    isConnectable: connectable == null
        ? null
        : objc.NSNumber.as(connectable).boolValue,
  );
}
