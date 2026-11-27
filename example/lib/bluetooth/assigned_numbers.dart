import 'package:bt_kit/bt_kit.dart';

import 'app_uuids.dart';

/// Human-readable names for common Bluetooth SIG Assigned Numbers.
abstract final class AssignedNumbers {
  static String? serviceName(BluetoothUuid uuid) =>
      _appServices[uuid] ?? _byShort(_services, uuid);

  static String? characteristicName(BluetoothUuid uuid) =>
      _byShort(_characteristics, uuid);

  static String? descriptorName(BluetoothUuid uuid) =>
      _byShort(_descriptors, uuid);

  static String? companyName(int id) => _companies[id];

  /// Formats a 16-bit company or UUID number as `0x004C`.
  static String hex16(int value) =>
      '0x${value.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  static String? _byShort(Map<int, String> table, BluetoothUuid uuid) {
    final short = uuid.shortValue;
    return short == null ? null : table[short];
  }

  static final _appServices = {
    AppUuids.beacon: 'BT Radar beacon',
    AppUuids.party: 'BT Radar party',
    AppUuids.fileBeam: 'BT Radar file beam',
    AppUuids.lab: 'BT Radar Lab reference',
  };

  static const _services = {
    0x1800: 'Generic Access',
    0x1801: 'Generic Attribute',
    0x1802: 'Immediate Alert',
    0x1803: 'Link Loss',
    0x1804: 'Tx Power',
    0x1805: 'Current Time',
    0x1808: 'Glucose',
    0x1809: 'Health Thermometer',
    0x180a: 'Device Information',
    0x180d: 'Heart Rate',
    0x180f: 'Battery',
    0x1810: 'Blood Pressure',
    0x1812: 'Human Interface Device',
    0x1814: 'Running Speed and Cadence',
    0x1816: 'Cycling Speed and Cadence',
    0x1818: 'Cycling Power',
    0x1819: 'Location and Navigation',
    0x181a: 'Environmental Sensing',
    0x181c: 'User Data',
    0x181d: 'Weight Scale',
    0x1822: 'Pulse Oximeter',
    0x1826: 'Fitness Machine',
    0x1827: 'Mesh Provisioning',
    0x1828: 'Mesh Proxy',
    0x1844: 'Volume Control',
    0x184e: 'Audio Stream Control',
    0x184f: 'Broadcast Audio Scan',
    0x1850: 'Published Audio Capabilities',
    0x1852: 'Broadcast Audio Announcement',
    0x1854: 'Hearing Access',
    0xfcb2: 'Apple',
    0xfd5a: 'Samsung SmartTag',
    0xfd69: 'Samsung SmartThings Find',
    0xfd6f: 'Exposure Notification',
    0xfe03: 'Amazon',
    0xfe07: 'Sonos',
    0xfe0f: 'Signify (Philips Hue)',
    0xfe2c: 'Google Fast Pair',
    0xfe95: 'Xiaomi',
    0xfe9a: 'Estimote',
    0xfe9f: 'Google',
    0xfeaa: 'Eddystone',
    0xfebe: 'Bose',
    0xfeec: 'Tile',
    0xfeed: 'Tile',
    0xfff6: 'Matter',
  };

  static const _characteristics = {
    0x2a00: 'Device Name',
    0x2a01: 'Appearance',
    0x2a04: 'Peripheral Preferred Connection Parameters',
    0x2a05: 'Service Changed',
    0x2a06: 'Alert Level',
    0x2a07: 'Tx Power Level',
    0x2a19: 'Battery Level',
    0x2a23: 'System ID',
    0x2a24: 'Model Number String',
    0x2a25: 'Serial Number String',
    0x2a26: 'Firmware Revision String',
    0x2a27: 'Hardware Revision String',
    0x2a28: 'Software Revision String',
    0x2a29: 'Manufacturer Name String',
    0x2a2b: 'Current Time',
    0x2a37: 'Heart Rate Measurement',
    0x2a38: 'Body Sensor Location',
    0x2a39: 'Heart Rate Control Point',
    0x2a4d: 'Report',
    0x2a50: 'PnP ID',
    0x2a5b: 'CSC Measurement',
    0x2a5c: 'CSC Feature',
    0x2a63: 'Cycling Power Measurement',
    0x2a6e: 'Temperature',
    0x2a6f: 'Humidity',
    0x2aa6: 'Central Address Resolution',
    0x2ac9: 'Resolvable Private Address Only',
    0x2b29: 'Client Supported Features',
    0x2b2a: 'Database Hash',
    0x2b3a: 'Server Supported Features',
  };

  static const _descriptors = {
    0x2900: 'Characteristic Extended Properties',
    0x2901: 'Characteristic User Description',
    0x2902: 'Client Characteristic Configuration',
    0x2903: 'Server Characteristic Configuration',
    0x2904: 'Characteristic Presentation Format',
  };

  static const _companies = {
    0x0002: 'Intel',
    0x0006: 'Microsoft',
    0x004c: 'Apple',
    0x0057: 'Harman',
    0x0059: 'Nordic Semiconductor',
    0x006b: 'Polar',
    0x0075: 'Samsung',
    0x0087: 'Garmin',
    0x009e: 'Bose',
    0x00c4: 'LG Electronics',
    0x00e0: 'Google',
    0x012d: 'Sony',
    0x0157: 'Zepp (Huami)',
    0x0171: 'Amazon',
    0x018e: 'Google',
    0x01da: 'Logitech',
    0x0499: 'Ruuvi',
    0x05a7: 'Sonos',
    0x0969: 'SwitchBot',
  };
}
