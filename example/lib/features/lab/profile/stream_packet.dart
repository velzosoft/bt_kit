import 'dart:typed_data';

/// One value of the notify or indicate stream: a little-endian uint32
/// sequence number, then a little-endian uint64 of microseconds since the
/// stream started.
final class StreamPacket {
  const StreamPacket(this.sequence, this.timestampMicros);

  static const length = 12;

  final int sequence;
  final int timestampMicros;

  Uint8List encode() {
    final data = ByteData(length)
      ..setUint32(0, sequence, Endian.little)
      ..setUint64(4, timestampMicros, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Null when [bytes] is not a stream packet.
  static StreamPacket? decode(List<int> bytes) {
    if (bytes.length != length) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    return StreamPacket(
      data.getUint32(0, Endian.little),
      data.getUint64(4, Endian.little),
    );
  }
}
