import 'dart:math';
import 'dart:typed_data';

import 'package:bt_radar/features/file_beam/protocol/beam_frame.dart';
import 'package:bt_radar/features/file_beam/protocol/beam_parser.dart';
import 'package:bt_radar/features/file_beam/protocol/crc32.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List frame(String name, List<int> payload, {int? crc}) =>
    Uint8List.fromList([
      ...BeamFrame.header(name, payload.length),
      ...payload,
      ...BeamFrame.trailer(crc ?? Crc32.of(payload)),
    ]);

/// Feeds [bytes] to a new parser in chunks of the given sizes, cycling
/// through them.
BeamParser parse(List<int> bytes, {List<int> chunkSizes = const [1 << 30]}) {
  final parser = BeamParser();
  var offset = 0;
  for (var i = 0; offset < bytes.length; i++) {
    final end = min(offset + chunkSizes[i % chunkSizes.length], bytes.length);
    parser.add(bytes.sublist(offset, end));
    offset = end;
  }
  parser.close();
  return parser;
}

Matcher throwsBeam(BeamFailure failure) => throwsA(
  isA<BeamFormatException>().having((e) => e.failure, 'failure', failure),
);

void main() {
  final random = Random(7);
  final payload = List.generate(5000, (_) => random.nextInt(256));

  group('header', () {
    test('lays out magic, version, name and a uint64 length', () {
      expect(BeamFrame.header('ab', 0x01020304), [
        ...'BEAM'.codeUnits,
        1,
        2,
        ...'ab'.codeUnits,
        ...[0x04, 0x03, 0x02, 0x01, 0, 0, 0, 0],
      ]);
    });

    test('rejects names longer than 255 bytes', () {
      expect(() => BeamFrame.header('x' * 256, 1), throwsArgumentError);
    });

    test('rejects payloads above the limit', () {
      expect(
        () => BeamFrame.header('x', BeamFrame.maxPayloadLength + 1),
        throwsRangeError,
      );
    });

    test('the trailer is the CRC-32, little-endian', () {
      expect(BeamFrame.trailer(0xcbf43926), [0x26, 0x39, 0xf4, 0xcb]);
    });
  });

  group('parsing', () {
    test('reads a frame that arrives in one chunk', () {
      final parser = parse(frame('photo.png', payload));
      expect(parser.header?.name, 'photo.png');
      expect(parser.header?.length, payload.length);
      expect(parser.payload, payload);
    });

    test('reads a frame split into chunks of every size', () {
      final bytes = frame('photo.png', payload);
      for (final size in [1, 2, 3, 5, 7, 13, 64, 1000, 4096]) {
        expect(parse(bytes, chunkSizes: [size]).payload, payload);
      }
    });

    test('reads a frame split at random places', () {
      final bytes = frame('photo.png', payload);
      for (var run = 0; run < 50; run++) {
        final sizes = List.generate(20, (_) => 1 + random.nextInt(600));
        final parser = parse(bytes, chunkSizes: sizes);
        expect(parser.header?.name, 'photo.png');
        expect(parser.payload, payload);
      }
    });

    test('keeps multi-byte UTF-8 names split across chunks', () {
      final parser = parse(frame('café ☕.png', [1, 2, 3]), chunkSizes: [1]);
      expect(parser.header?.name, 'café ☕.png');
    });

    test('accepts an empty name and an empty payload', () {
      final parser = parse(frame('', []), chunkSizes: [1]);
      expect(parser.header?.name, '');
      expect(parser.payload, isEmpty);
    });

    test('announces the header before the payload arrives', () {
      final parser = BeamParser();
      final header = BeamFrame.header('a.bin', payload.length);
      parser.add(header.sublist(0, header.length - 1));
      expect(parser.header, isNull);
      parser.add([header.last, ...payload.take(100)]);
      expect(parser.header?.length, payload.length);
      expect(parser.received, 100);
      expect(parser.isComplete, isFalse);
    });
  });

  group('failures', () {
    test('bad magic fails as soon as four bytes arrive', () {
      final parser = BeamParser()..add('BEA'.codeUnits);
      expect(() => parser.add('R'.codeUnits), throwsBeam(BeamFailure.badMagic));
    });

    test('an unknown version fails', () {
      final bytes = frame('a', payload)..[4] = 2;
      expect(() => parse(bytes), throwsBeam(BeamFailure.unsupportedVersion));
    });

    test('a name that is not UTF-8 fails', () {
      final bytes = frame('ab', payload)..[6] = 0xff;
      expect(() => parse(bytes), throwsBeam(BeamFailure.badName));
    });

    test('a length above the limit fails before any payload', () {
      final bytes = frame('a', payload);
      ByteData.sublistView(bytes).setUint32(11, 1, Endian.little);
      final parser = BeamParser();
      expect(
        () => parser.add(bytes.sublist(0, 15)),
        throwsBeam(BeamFailure.tooLarge),
      );
    });

    test('a length beyond the parser limit fails', () {
      final parser = BeamParser(maxPayloadLength: 100);
      expect(
        () => parser.add(BeamFrame.header('a', 101)),
        throwsBeam(BeamFailure.tooLarge),
      );
    });

    test('a damaged payload fails the checksum', () {
      final bytes = frame('a', payload)..[100] ^= 0x01;
      expect(
        () => parse(bytes, chunkSizes: [512]),
        throwsBeam(BeamFailure.checksumMismatch),
      );
    });

    test('a wrong trailer fails the checksum', () {
      final bytes = frame('a', payload, crc: Crc32.of(payload) ^ 1);
      expect(() => parse(bytes), throwsBeam(BeamFailure.checksumMismatch));
    });

    test('input that ends early is truncated', () {
      final bytes = frame('a', payload);
      for (final cut in [0, 3, 10, 200, bytes.length - 1]) {
        expect(
          () => parse(bytes.sublist(0, cut)),
          throwsBeam(BeamFailure.truncated),
          reason: 'cut after $cut bytes',
        );
      }
    });

    test('bytes after the trailer fail', () {
      final bytes = [...frame('a', payload), 0];
      expect(() => parse(bytes), throwsBeam(BeamFailure.unexpectedBytes));
    });

    test('the payload is unavailable until the transfer completes', () {
      final parser = BeamParser()..add(BeamFrame.header('a', 10));
      expect(() => parser.payload, throwsStateError);
    });
  });
}
