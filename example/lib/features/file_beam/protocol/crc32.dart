import 'dart:typed_data';

/// CRC-32 as used by zlib, PNG and Ethernet: reflected, polynomial
/// `0xEDB88320`, initial value and final XOR `0xFFFFFFFF`.
final class Crc32 {
  static final _table = _buildTable();

  var _register = 0xffffffff;

  int get value => _register ^ 0xffffffff;

  /// Adds `bytes[start..end)` to the checksum.
  void add(List<int> bytes, [int start = 0, int? end]) {
    var register = _register;
    final stop = end ?? bytes.length;
    for (var i = start; i < stop; i++) {
      register = _table[(register ^ bytes[i]) & 0xff] ^ (register >>> 8);
    }
    _register = register;
  }

  static int of(List<int> bytes) => (Crc32()..add(bytes)).value;

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var bit = 0; bit < 8; bit++) {
        c = c & 1 == 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      }
      table[n] = c;
    }
    return table;
  }
}
