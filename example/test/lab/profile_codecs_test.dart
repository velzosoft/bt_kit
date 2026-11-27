import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/lab/profile/fault_command.dart';
import 'package:bt_radar/features/lab/profile/stream_command.dart';
import 'package:bt_radar/features/lab/profile/stream_packet.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher rejectsWith(GattError error) =>
    throwsA(isA<GattException>().having((e) => e.error, 'error', error));

void main() {
  group('StreamPacket', () {
    test('is a little-endian uint32 sequence and uint64 timestamp', () {
      final bytes = const StreamPacket(0x01020304, 0x0a0b0c0d0e).encode();
      expect(bytes, [4, 3, 2, 1, 0x0e, 0x0d, 0x0c, 0x0b, 0x0a, 0, 0, 0]);
    });

    test('round-trips large values', () {
      final packet = StreamPacket.decode(
        const StreamPacket(0xffffffff, 600000000000).encode(),
      )!;
      expect(packet.sequence, 0xffffffff);
      expect(packet.timestampMicros, 600000000000);
    });

    test('is null for any other length', () {
      expect(StreamPacket.decode(const [1, 2, 3]), isNull);
      expect(StreamPacket.decode(List.filled(13, 0)), isNull);
    });
  });

  group('StreamCommand', () {
    test('encodes the documented bytes', () {
      expect(const StopStream().encode(), [0x00]);
      expect(const StartStream(StreamKind.notify, 50).encode(), [1, 50, 0]);
      expect(const StartStream(StreamKind.indicate, 1000).encode(), [
        2,
        0xe8,
        0x03,
      ]);
    });

    test('round-trips', () {
      for (final command in const [
        StopStream(),
        StartStream(StreamKind.notify, 1),
        StartStream(StreamKind.indicate, 1000),
      ]) {
        expect(StreamCommand.decode(command.encode()), command);
      }
    });

    test('rejects the wrong length', () {
      expect(
        () => StreamCommand.decode(const []),
        rejectsWith(GattError.invalidAttributeValueLength),
      );
      expect(
        () => StreamCommand.decode(const [0, 0]),
        rejectsWith(GattError.invalidAttributeValueLength),
      );
      expect(
        () => StreamCommand.decode(const [1, 50]),
        rejectsWith(GattError.invalidAttributeValueLength),
      );
    });

    test('rejects unknown commands and rates out of range', () {
      expect(
        () => StreamCommand.decode(const [3, 50, 0]),
        rejectsWith(GattError.valueNotAllowed),
      );
      expect(
        () => StreamCommand.decode(const [1, 0, 0]),
        rejectsWith(GattError.valueNotAllowed),
      );
      expect(
        () => StreamCommand.decode(const [1, 0xe9, 0x03]),
        rejectsWith(GattError.valueNotAllowed),
      );
    });
  });

  group('FaultCommand', () {
    test('zero clears the fault', () {
      expect(FaultCommand.decode(const [0]), isNull);
      expect(FaultCommand.encode(null), [0]);
    });

    test('an ATT error code sets it', () {
      expect(FaultCommand.decode(const [0x02]), GattError.readNotPermitted);
      expect(FaultCommand.encode(GattError.unlikelyError), [0x0e]);
    });

    test('rejects unknown codes and the wrong length', () {
      expect(
        () => FaultCommand.decode(const [0x80]),
        rejectsWith(GattError.valueNotAllowed),
      );
      expect(
        () => FaultCommand.decode(const [2, 0]),
        rejectsWith(GattError.invalidAttributeValueLength),
      );
    });
  });
}
