import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import 'reference_profile.dart';

enum StreamKind { notify, indicate }

/// A value of the stream control characteristic.
///
/// | Bytes | Meaning |
/// |---|---|
/// | `00` | Stop streaming |
/// | `01 rr rr` | Notify a packet `rrrr` times a second (uint16 LE) |
/// | `02 rr rr` | Indicate a packet `rrrr` times a second |
sealed class StreamCommand {
  const StreamCommand();

  Uint8List encode();

  /// Throws the [GattException] the reference answers an invalid write with.
  static StreamCommand decode(List<int> bytes) {
    if (bytes.isEmpty) throw _reject(GattError.invalidAttributeValueLength);
    final kind = switch (bytes[0]) {
      0x00 => null,
      0x01 => StreamKind.notify,
      0x02 => StreamKind.indicate,
      _ => throw _reject(GattError.valueNotAllowed),
    };
    if (kind == null) {
      if (bytes.length != 1) {
        throw _reject(GattError.invalidAttributeValueLength);
      }
      return const StopStream();
    }
    if (bytes.length != 3) throw _reject(GattError.invalidAttributeValueLength);
    final rate = bytes[1] | bytes[2] << 8;
    if (rate < 1 || rate > ReferenceProfile.maxRateHz) {
      throw _reject(GattError.valueNotAllowed);
    }
    return StartStream(kind, rate);
  }

  static GattException _reject(GattError error) =>
      GattException(error, 'stream control');
}

final class StopStream extends StreamCommand {
  const StopStream();

  @override
  Uint8List encode() => Uint8List.fromList(const [0x00]);

  @override
  bool operator ==(Object other) => other is StopStream;

  @override
  int get hashCode => 0;
}

final class StartStream extends StreamCommand {
  const StartStream(this.kind, this.rateHz);

  final StreamKind kind;
  final int rateHz;

  @override
  Uint8List encode() => Uint8List.fromList([
    kind == StreamKind.notify ? 0x01 : 0x02,
    rateHz & 0xff,
    rateHz >> 8 & 0xff,
  ]);

  @override
  bool operator ==(Object other) =>
      other is StartStream && other.kind == kind && other.rateHz == rateHz;

  @override
  int get hashCode => Object.hash(kind, rateHz);
}
