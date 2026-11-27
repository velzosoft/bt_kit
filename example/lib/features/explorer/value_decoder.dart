import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import '../../bluetooth/assigned_numbers.dart';
import 'appearance.dart';

typedef _Decode = String? Function(ByteData data);

/// Reads attribute values the way a person would: what a well-known value
/// means, such as `87 %`, or the text a value holds, in quotes.
abstract final class ValueDecoder {
  static String? characteristic(BluetoothUuid uuid, List<int> bytes) =>
      _known(_characteristics, uuid, bytes) ?? _quotedText(bytes);

  static String? descriptor(BluetoothUuid uuid, List<int> bytes) =>
      _known(_descriptors, uuid, bytes) ?? _quotedText(bytes);

  /// [bytes] as UTF-8 when every character is printable. Trailing NUL bytes,
  /// which end C strings and pad fixed-size fields, are dropped.
  static String? printableText(List<int> bytes) {
    final trimmed = _withoutTrailingNul(bytes);
    if (trimmed.isEmpty) return null;
    try {
      final text = utf8.decode(trimmed);
      return text.runes.every(_isPrintable) ? text : null;
    } on FormatException {
      return null;
    }
  }

  static List<int> _withoutTrailingNul(List<int> bytes) {
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end--;
    }
    return bytes.sublist(0, end);
  }

  static bool _isPrintable(int rune) =>
      rune == 0x09 ||
      rune == 0x0a ||
      rune == 0x0d ||
      (rune >= 0x20 && rune != 0x7f && (rune < 0x80 || rune > 0x9f));

  /// One printable byte is more often a number than a character.
  static String? _quotedText(List<int> bytes) {
    if (bytes.length < 2) return null;
    final text = printableText(bytes);
    return text == null ? null : '“$text”';
  }

  static String? _known(
    Map<int, (int, _Decode)> table,
    BluetoothUuid uuid,
    List<int> bytes,
  ) {
    final entry = table[uuid.shortValue];
    if (entry == null) return null;
    final (minimumLength, decode) = entry;
    if (bytes.length < minimumLength) return null;
    return decode(ByteData.sublistView(Uint8List.fromList(bytes)));
  }

  /// Keyed by the 16-bit UUID, with the shortest valid value.
  static const Map<int, (int, _Decode)> _characteristics = {
    0x2a00: (1, _string),
    0x2a01: (2, _appearance),
    0x2a04: (8, _connectionParameters),
    0x2a05: (4, _handleRange),
    0x2a06: (1, _alertLevel),
    0x2a07: (1, _txPower),
    0x2a08: (7, _dateTime),
    0x2a19: (1, _batteryLevel),
    0x2a1c: (5, _temperatureMeasurement),
    0x2a24: (1, _string),
    0x2a25: (1, _string),
    0x2a26: (1, _string),
    0x2a27: (1, _string),
    0x2a28: (1, _string),
    0x2a29: (1, _string),
    0x2a2b: (7, _dateTime),
    0x2a37: (2, _heartRate),
    0x2a38: (1, _bodySensorLocation),
    0x2a50: (7, _pnpId),
    0x2a6e: (2, _temperature),
    0x2a6f: (2, _humidity),
    0x2aa6: (1, _supported),
  };

  static const Map<int, (int, _Decode)> _descriptors = {
    0x2900: (1, _extendedProperties),
    0x2901: (1, _string),
    0x2902: (1, _clientConfiguration),
    0x2904: (4, _presentationFormat),
    0x2908: (2, _reportReference),
  };

  static String? _string(ByteData data) {
    final bytes = _withoutTrailingNul(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    if (bytes.isEmpty) return null;
    return '“${utf8.decode(bytes, allowMalformed: true)}”';
  }

  static String _appearance(ByteData data) =>
      Appearance.describe(_uint16(data, 0));

  static String _connectionParameters(ByteData data) {
    final minimum = _uint16(data, 0) * 1.25;
    final maximum = _uint16(data, 2) * 1.25;
    final latency = _uint16(data, 4);
    final timeout = _uint16(data, 6) * 10;
    return 'Interval ${_number(minimum)}–${_number(maximum)} ms · '
        'latency $latency · timeout $timeout ms';
  }

  static String _handleRange(ByteData data) =>
      'Handles ${AssignedNumbers.hex16(_uint16(data, 0))}–'
      '${AssignedNumbers.hex16(_uint16(data, 2))}';

  static String? _alertLevel(ByteData data) => switch (data.getUint8(0)) {
    0 => 'No alert',
    1 => 'Mild alert',
    2 => 'High alert',
    _ => null,
  };

  static String _txPower(ByteData data) => '${data.getInt8(0)} dBm';

  static String? _dateTime(ByteData data) {
    final year = _uint16(data, 0);
    final values = [for (var i = 2; i < 7; i++) data.getUint8(i)];
    if (year == 0 || values[0] == 0 || values[1] == 0) return null;
    final [month, day, hour, minute, second] = [
      for (final value in values) value.toString().padLeft(2, '0'),
    ];
    return '$year-$month-$day $hour:$minute:$second';
  }

  static String _batteryLevel(ByteData data) => '${data.getUint8(0)} %';

  /// The value is an IEEE 11073 32-bit FLOAT: a 24-bit mantissa and an 8-bit
  /// exponent, both signed.
  static String? _temperatureMeasurement(ByteData data) {
    final raw = data.getUint32(1, Endian.little);
    final mantissa = (raw & 0xffffff).toSigned(24);
    final exponent = (raw >> 24).toSigned(8);
    if (mantissa.abs() >= 0x7ffffe) return null;
    final unit = data.getUint8(0) & 0x01 == 0 ? '°C' : '°F';
    return '${_number(mantissa * pow(10, exponent))} $unit';
  }

  /// Flags bit 0 picks a uint8 or uint16 value; bits 1–2 report skin
  /// contact when the sensor supports detecting it.
  static String? _heartRate(ByteData data) {
    final flags = data.getUint8(0);
    final wide = flags & 0x01 != 0;
    if (wide && data.lengthInBytes < 3) return null;
    final bpm = wide ? _uint16(data, 1) : data.getUint8(1);
    final noContact = (flags >> 1) & 0x03 == 0x02;
    return noContact ? '$bpm bpm · no skin contact' : '$bpm bpm';
  }

  static String? _bodySensorLocation(ByteData data) =>
      switch (data.getUint8(0)) {
        0 => 'Other',
        1 => 'Chest',
        2 => 'Wrist',
        3 => 'Finger',
        4 => 'Hand',
        5 => 'Ear lobe',
        6 => 'Foot',
        _ => null,
      };

  static String? _pnpId(ByteData data) {
    final vendor = _uint16(data, 1);
    final vendorText = switch (data.getUint8(0)) {
      1 =>
        '${AssignedNumbers.companyName(vendor) ?? 'Vendor'} '
            '${AssignedNumbers.hex16(vendor)}',
      2 => 'USB vendor ${AssignedNumbers.hex16(vendor)}',
      _ => null,
    };
    if (vendorText == null) return null;
    return '$vendorText · product ${AssignedNumbers.hex16(_uint16(data, 3))}'
        ' · version ${AssignedNumbers.hex16(_uint16(data, 5))}';
  }

  static String _temperature(ByteData data) =>
      '${_number(data.getInt16(0, Endian.little) / 100)} °C';

  static String _humidity(ByteData data) =>
      '${_number(_uint16(data, 0) / 100)} %';

  static String _supported(ByteData data) =>
      data.getUint8(0) == 1 ? 'Supported' : 'Not supported';

  static String _extendedProperties(ByteData data) {
    final bits = data.getUint8(0);
    final names = [
      if (bits & 0x01 != 0) 'Reliable write',
      if (bits & 0x02 != 0) 'Writable auxiliaries',
    ];
    return names.isEmpty ? 'None' : names.join(', ');
  }

  static String _clientConfiguration(ByteData data) =>
      switch (data.getUint8(0) & 0x03) {
        0x01 => 'Notifications on',
        0x02 => 'Indications on',
        0x03 => 'Notifications and indications on',
        _ => 'Off',
      };

  static String _presentationFormat(ByteData data) {
    final format = _formats[data.getUint8(0)] ?? 'Format 0x${_hex8(data, 0)}';
    final exponent = data.getInt8(1);
    final unitNumber = _uint16(data, 2);
    final unit =
        _units[unitNumber] ?? 'unit ${AssignedNumbers.hex16(unitNumber)}';
    return [format, unit, if (exponent != 0) '×10^$exponent'].join(' · ');
  }

  static String? _reportReference(ByteData data) {
    final type = switch (data.getUint8(1)) {
      1 => 'input',
      2 => 'output',
      3 => 'feature',
      _ => null,
    };
    return type == null ? null : 'Report ${data.getUint8(0)} · $type';
  }

  static int _uint16(ByteData data, int offset) =>
      data.getUint16(offset, Endian.little);

  static String _hex8(ByteData data, int offset) =>
      data.getUint8(offset).toRadixString(16).padLeft(2, '0').toUpperCase();

  /// At most two decimals, without trailing zeros: `7.5`, `21.53`, `15`.
  static String _number(num value) => value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');

  static const _formats = {
    0x01: 'boolean',
    0x02: '2-bit',
    0x03: 'nibble',
    0x04: 'uint8',
    0x05: 'uint12',
    0x06: 'uint16',
    0x07: 'uint24',
    0x08: 'uint32',
    0x09: 'uint48',
    0x0a: 'uint64',
    0x0b: 'uint128',
    0x0c: 'sint8',
    0x0d: 'sint12',
    0x0e: 'sint16',
    0x0f: 'sint24',
    0x10: 'sint32',
    0x11: 'sint48',
    0x12: 'sint64',
    0x13: 'sint128',
    0x14: 'float32',
    0x15: 'float64',
    0x16: 'SFLOAT',
    0x17: 'FLOAT',
    0x18: 'duint16',
    0x19: 'UTF-8 string',
    0x1a: 'UTF-16 string',
    0x1b: 'struct',
  };

  static const _units = {
    0x2700: 'unitless',
    0x2701: 'metres',
    0x2702: 'kilograms',
    0x2703: 'seconds',
    0x2704: 'amperes',
    0x2705: 'kelvin',
    0x2722: 'hertz',
    0x2724: 'pascals',
    0x2726: 'watts',
    0x2728: 'volts',
    0x272f: '°C',
    0x27ad: 'percent',
    0x27af: 'beats per minute',
  };
}
