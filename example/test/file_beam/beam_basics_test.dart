import 'dart:math';

import 'package:bt_radar/features/file_beam/protocol/beam_link.dart';
import 'package:bt_radar/features/file_beam/transfer/beam_payload.dart';
import 'package:bt_radar/features/file_beam/transfer/transfer_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PSM characteristic', () {
    test('encodes a uint16, little-endian', () {
      expect(BeamLink.encodePsm(0x0081), [0x81, 0x00]);
      expect(BeamLink.encodePsm(0x1234), [0x34, 0x12]);
    });

    test('decodes what it encodes', () {
      expect(BeamLink.decodePsm(BeamLink.encodePsm(0x00c5)), 0x00c5);
    });

    test('rejects malformed values', () {
      expect(BeamLink.decodePsm([0x81]), isNull);
      expect(BeamLink.decodePsm([0x81, 0, 0]), isNull);
      expect(BeamLink.decodePsm([0, 0]), isNull);
    });
  });

  group('payloads', () {
    test('the throughput test is 1 MB of random bytes', () {
      final payload = BeamPayload.test(random: Random(1));
      expect(payload.bytes.length, 1024 * 1024);
      expect(payload.bytes.toSet().length, 256);
      expect(hasPngSignature(payload.bytes), isFalse);
    });

    test('recognizes a PNG by its signature', () {
      const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
      expect(hasPngSignature([...signature, 0, 0]), isTrue);
      expect(hasPngSignature(signature.take(7).toList()), isFalse);
      expect(hasPngSignature([0xff, ...signature.skip(1)]), isFalse);
    });
  });

  group('units', () {
    test('sizes', () {
      expect(TransferUnits.bytes(512), '512 B');
      expect(TransferUnits.bytes(1024), '1 KB');
      expect(TransferUnits.bytes(1536), '1.5 KB');
      expect(TransferUnits.bytes(150 * 1024), '150 KB');
      expect(TransferUnits.bytes(1024 * 1024), '1 MB');
      expect(TransferUnits.bytes(1536 * 1024), '1.5 MB');
    });

    test('rates in KB/s', () {
      expect(TransferUnits.kilobytesPerSecond(0), '0');
      expect(TransferUnits.kilobytesPerSecond(8.5 * 1024), '8.5');
      expect(TransferUnits.kilobytesPerSecond(85.4 * 1024), '85');
    });

    test('durations', () {
      expect(
        TransferUnits.duration(const Duration(milliseconds: 420)),
        '0.4 s',
      );
      expect(TransferUnits.duration(const Duration(seconds: 12)), '12.0 s');
      expect(
        TransferUnits.duration(const Duration(minutes: 1, seconds: 5)),
        '1 min 05 s',
      );
    });
  });
}
