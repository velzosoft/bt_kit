import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import '../model/failure_tally.dart';
import '../profile/stream_command.dart';
import '../profile/stream_packet.dart';

typedef SendPacket = Future<void> Function(
  LocalCharacteristic characteristic,
  Uint8List value,
);

/// Sends [StreamPacket]s at a fixed rate, one at a time. Each packet is due
/// at `sequence / rate` after the start; when sending falls behind, the
/// next ones go out at once until it catches up.
final class StreamPump {
  StreamPump(this._send);

  final SendPacket _send;
  var _generation = 0;
  StartStream? _command;
  var sent = 0;
  var failed = 0;
  String? lastError;

  StartStream? get command => _command;

  void start(LocalCharacteristic characteristic, StartStream command) {
    final generation = ++_generation;
    _command = command;
    unawaited(_run(generation, characteristic, command.rateHz));
  }

  void stop() {
    _generation++;
    _command = null;
  }

  Future<void> _run(
    int generation,
    LocalCharacteristic characteristic,
    int rateHz,
  ) async {
    final period = Duration(
      microseconds: Duration.microsecondsPerSecond ~/ rateHz,
    );
    final clock = Stopwatch()..start();
    try {
      for (var sequence = 0; generation == _generation; sequence++) {
        final wait = period * sequence - clock.elapsed;
        if (wait > Duration.zero) await Future<void>.delayed(wait);
        if (generation != _generation) return;
        final packet = StreamPacket(sequence, clock.elapsedMicroseconds);
        try {
          await _send(characteristic, packet.encode());
          sent++;
        } on BluetoothException catch (e) {
          failed++;
          lastError = FailureTally.describe(e);
        }
      }
    } on Object catch (e) {
      lastError = '$e';
      if (generation == _generation) stop();
    }
  }
}
