import 'dart:convert';

import 'package:bt_radar/features/file_beam/protocol/crc32.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vectors = {
    '': 0x00000000,
    'a': 0xe8b7be43,
    'abc': 0x352441c2,
    '123456789': 0xcbf43926,
    'The quick brown fox jumps over the lazy dog': 0x414fa339,
  };

  for (final MapEntry(key: text, value: crc) in vectors.entries) {
    test('"$text" has CRC-32 0x${crc.toRadixString(16)}', () {
      expect(Crc32.of(utf8.encode(text)), crc);
    });
  }

  test('32 zero bytes', () {
    expect(Crc32.of(List.filled(32, 0)), 0x190a55ad);
  });

  test('every byte value once', () {
    expect(Crc32.of(List.generate(256, (i) => i)), 0x29058c73);
  });

  test('adding in pieces equals adding at once', () {
    final bytes = utf8.encode('The quick brown fox jumps over the lazy dog');
    final crc = Crc32()
      ..add(bytes, 0, 10)
      ..add(bytes, 10, 11)
      ..add(bytes, 11);
    expect(crc.value, 0x414fa339);
  });
}
