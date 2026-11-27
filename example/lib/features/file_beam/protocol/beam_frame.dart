import 'dart:convert';
import 'dart:typed_data';

/// The File beam wire format. Integers are little-endian.
///
/// | Bytes | Field |
/// |---|---|
/// | 4 | Magic, `BEAM` |
/// | 1 | Version, 1 |
/// | 1 | Name length N |
/// | N | Name, UTF-8 |
/// | 8 | Payload length L |
/// | L | Payload |
/// | 4 | CRC-32 of the payload |
///
/// The receiver answers with one byte: [ack] when the checksum matches,
/// [nak] when it does not.
abstract final class BeamFrame {
  static const magic = [0x42, 0x45, 0x41, 0x4d];
  static const version = 1;
  static const maxNameLength = 255;
  static const maxPayloadLength = 64 * 1024 * 1024;
  static const trailerLength = 4;
  static const ack = 0x06;
  static const nak = 0x15;

  static Uint8List header(String name, int payloadLength) {
    final encodedName = utf8.encode(name);
    if (encodedName.length > maxNameLength) {
      throw ArgumentError.value(name, 'name', 'longer than 255 bytes');
    }
    RangeError.checkValueInInterval(
      payloadLength,
      0,
      maxPayloadLength,
      'payloadLength',
    );
    final nameEnd = magic.length + 2 + encodedName.length;
    final bytes = Uint8List(nameEnd + 8)
      ..setAll(0, magic)
      ..[magic.length] = version
      ..[magic.length + 1] = encodedName.length
      ..setAll(magic.length + 2, encodedName);
    ByteData.sublistView(bytes)
      ..setUint32(nameEnd, payloadLength, Endian.little)
      ..setUint32(nameEnd + 4, 0, Endian.little);
    return bytes;
  }

  static Uint8List trailer(int crc) =>
      Uint8List(trailerLength)
        ..buffer.asByteData().setUint32(0, crc, Endian.little);
}

/// What a received header announces.
final class BeamHeader {
  const BeamHeader(this.name, this.length);

  final String name;
  final int length;
}

enum BeamFailure {
  badMagic,
  unsupportedVersion,
  badName,
  tooLarge,
  checksumMismatch,
  truncated,
  unexpectedBytes,
}

final class BeamFormatException implements Exception {
  const BeamFormatException(this.failure);

  final BeamFailure failure;

  @override
  String toString() => 'BeamFormatException: ${failure.name}';
}
