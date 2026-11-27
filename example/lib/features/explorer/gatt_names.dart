import 'package:bt_kit/bt_kit.dart';

import '../../bluetooth/assigned_numbers.dart';

/// Names for GATT attributes: the app's Assigned Numbers table, plus
/// attributes that mostly matter once connected.
abstract final class GattNames {
  static String service(BluetoothUuid uuid) =>
      AssignedNumbers.serviceName(uuid) ??
      _services['$uuid'] ??
      _fallback(uuid, 'service');

  static String characteristic(BluetoothUuid uuid) =>
      AssignedNumbers.characteristicName(uuid) ??
      _characteristics['$uuid'] ??
      _fallback(uuid, 'characteristic');

  static String descriptor(BluetoothUuid uuid) =>
      AssignedNumbers.descriptorName(uuid) ??
      _descriptors['$uuid'] ??
      _fallback(uuid, 'descriptor');

  /// `0x180D` for assigned 16-bit numbers, otherwise the full UUID.
  static String uuid(BluetoothUuid uuid) => switch (uuid.shortValue) {
    final short? when short <= 0xffff => AssignedNumbers.hex16(short),
    _ => uuid.value,
  };

  static String _fallback(BluetoothUuid uuid, String kind) =>
      uuid.shortValue == null ? 'Vendor-specific $kind' : 'Unnamed $kind';

  static const _services = {
    '1811': 'Alert Notification',
    '181e': 'Bond Management',
    '181f': 'Continuous Glucose Monitoring',
    'fe59': 'Nordic DFU',
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e': 'Nordic UART',
    '00001523-1212-efde-1523-785feabcd123': 'Nordic LED Button',
    '7905f431-b5ce-4e99-a40f-4b1e122d00d0': 'Apple Notification Center',
    '89d3502b-0f36-433a-8ef4-c502ad55f8dc': 'Apple Media',
    'd0611e78-bbb4-4591-a5f8-487910ae4366': 'Apple Continuity',
  };

  static const _characteristics = {
    '2a08': 'Date Time',
    '2a0f': 'Local Time Information',
    '2a1c': 'Temperature Measurement',
    '2a1d': 'Temperature Type',
    '2a1e': 'Intermediate Temperature',
    '2a22': 'Boot Keyboard Input Report',
    '2a32': 'Boot Keyboard Output Report',
    '2a33': 'Boot Mouse Input Report',
    '2a35': 'Blood Pressure Measurement',
    '2a46': 'New Alert',
    '2a49': 'Blood Pressure Feature',
    '2a4a': 'HID Information',
    '2a4b': 'Report Map',
    '2a4c': 'HID Control Point',
    '2a4e': 'Protocol Mode',
    '2a53': 'RSC Measurement',
    '2a54': 'RSC Feature',
    '2a5d': 'Sensor Location',
    '2a5f': 'PLX Continuous Measurement',
    '2a65': 'Cycling Power Feature',
    '2a6d': 'Pressure',
    '2a9d': 'Weight Measurement',
    '2a9e': 'Weight Scale Feature',
    '2acc': 'Fitness Machine Feature',
    '2ad2': 'Indoor Bike Data',
    '6e400002-b5a3-f393-e0a9-e50e24dcca9e': 'UART RX',
    '6e400003-b5a3-f393-e0a9-e50e24dcca9e': 'UART TX',
    '00001524-1212-efde-1523-785feabcd123': 'Button',
    '00001525-1212-efde-1523-785feabcd123': 'LED',
    '9fbf120d-6301-42d9-8c58-25e699a21dbd': 'Notification Source',
    '69d1d8f3-45e1-49a8-9821-9bbdfdaad9d9': 'Control Point',
    '22eac6e9-24d6-4bb5-be44-b36ace7c7bfb': 'Data Source',
    '9b3c81d8-57b1-4a8a-b8df-0e56f7ca51c2': 'Remote Command',
    '2f7cabce-808d-411f-9a0c-bb92ba96c102': 'Entity Update',
    'c6b2f38c-23ab-46d8-a6ab-a3a870bbd5d7': 'Entity Attribute',
  };

  static const _descriptors = {
    '2905': 'Characteristic Aggregate Format',
    '2906': 'Valid Range',
    '2907': 'External Report Reference',
    '2908': 'Report Reference',
  };
}
