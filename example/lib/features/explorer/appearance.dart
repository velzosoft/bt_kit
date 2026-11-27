import '../../bluetooth/assigned_numbers.dart';

/// GAP Appearance values, from the Bluetooth SIG Assigned Numbers.
abstract final class Appearance {
  /// Such as `Watch (0x00C1)`.
  static String describe(int value) {
    final category = _categories[value >> 6] ?? 'Unknown';
    return '$category (${AssignedNumbers.hex16(value)})';
  }

  /// Keyed by the category, the top 10 bits of the value.
  static const _categories = {
    0x000: 'Unknown',
    0x001: 'Phone',
    0x002: 'Computer',
    0x003: 'Watch',
    0x004: 'Clock',
    0x005: 'Display',
    0x006: 'Remote control',
    0x007: 'Eyeglasses',
    0x008: 'Tag',
    0x009: 'Keyring',
    0x00a: 'Media player',
    0x00b: 'Barcode scanner',
    0x00c: 'Thermometer',
    0x00d: 'Heart rate sensor',
    0x00e: 'Blood pressure',
    0x00f: 'Human interface device',
    0x010: 'Glucose meter',
    0x011: 'Running walking sensor',
    0x012: 'Cycling',
    0x013: 'Control device',
    0x014: 'Network device',
    0x015: 'Sensor',
    0x016: 'Light fixture',
    0x017: 'Fan',
    0x018: 'HVAC',
    0x019: 'Air conditioning',
    0x01a: 'Humidifier',
    0x01b: 'Heating',
    0x01c: 'Access control',
    0x01d: 'Motorized device',
    0x01e: 'Power device',
    0x01f: 'Light source',
    0x020: 'Window covering',
    0x021: 'Audio sink',
    0x022: 'Audio source',
    0x023: 'Motorized vehicle',
    0x024: 'Domestic appliance',
    0x025: 'Wearable audio device',
    0x026: 'Aircraft',
    0x027: 'AV equipment',
    0x028: 'Display equipment',
    0x029: 'Hearing aid',
    0x02a: 'Gaming',
    0x02b: 'Signage',
    0x031: 'Pulse oximeter',
    0x032: 'Weight scale',
    0x033: 'Personal mobility device',
    0x034: 'Continuous glucose monitor',
    0x035: 'Insulin pump',
    0x036: 'Medication delivery',
    0x037: 'Spirometer',
    0x051: 'Outdoor sports activity',
  };
}
