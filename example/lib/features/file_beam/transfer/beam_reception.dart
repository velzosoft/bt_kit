import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import '../protocol/beam_frame.dart';
import '../protocol/beam_parser.dart';
import 'beam_payload.dart';
import 'beam_problem.dart';
import 'transfer_monitor.dart';

enum ReceptionStage { connected, receiving, received, failed }

/// A file that arrived with a matching checksum.
final class ReceivedFile {
  const ReceivedFile({
    required this.name,
    required this.bytes,
    required this.elapsed,
    required this.bytesPerSecond,
  });

  final String name;
  final Uint8List bytes;
  final Duration elapsed;
  final double bytesPerSecond;

  bool get isPng => hasPngSignature(bytes);
}

/// Receives one transfer on one L2CAP channel and answers the sender.
final class BeamReception {
  BeamReception(this._channel, this._onChange) {
    _input = _channel.input.listen(
      _onChunk,
      onDone: _onEnd,
      onError: (Object _) => _onEnd(),
    );
  }

  /// After answering, the sender closes the channel, so that the answer is
  /// not cut off. This closes it if the sender does not.
  static const _closeGrace = Duration(seconds: 5);

  final L2capChannel _channel;
  final void Function() _onChange;
  final _parser = BeamParser();
  late final StreamSubscription<Uint8List> _input;
  TransferMonitor? _monitor;
  ReceivedFile? _file;
  BeamProblem? _problem;
  Timer? _closeTimer;
  var _closed = false;

  BeamHeader? get header => _parser.header;

  TransferMonitor? get monitor => _monitor;

  ReceivedFile? get file => _file;

  BeamProblem? get problem => _problem;

  bool get isClosed => _closed;

  ReceptionStage get stage => switch ((_file, _problem, _monitor)) {
    (_?, _, _) => ReceptionStage.received,
    (_, _?, _) => ReceptionStage.failed,
    (_, _, _?) => ReceptionStage.receiving,
    _ => ReceptionStage.connected,
  };

  bool get isActive =>
      stage == ReceptionStage.connected || stage == ReceptionStage.receiving;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closeTimer?.cancel();
    await _input.cancel();
    await _channel.close();
    _onChange();
  }

  void _onChunk(Uint8List chunk) {
    if (!isActive) return;
    try {
      final before = _parser.received;
      _parser.add(chunk);
      _track(_parser.received - before);
      if (_parser.isComplete) _succeed();
    } on BeamFormatException catch (e) {
      _fail(e);
    }
  }

  /// Measures from the moment the header has arrived.
  void _track(int payloadBytes) {
    final header = _parser.header;
    if (header == null) return;
    if (_monitor case final monitor?) return monitor.add(payloadBytes);
    _monitor = TransferMonitor(header.length)..add(payloadBytes);
    _onChange();
  }

  void _succeed() {
    final monitor = _monitor!..finish();
    _file = ReceivedFile(
      name: header!.name,
      bytes: _parser.payload,
      elapsed: monitor.elapsed,
      bytesPerSecond: monitor.averageBytesPerSecond,
    );
    _answer(BeamFrame.ack);
    _onChange();
  }

  void _fail(BeamFormatException error) {
    _monitor?.finish();
    _problem = BeamProblem.of(error);
    if (error.failure == BeamFailure.checksumMismatch) {
      _answer(BeamFrame.nak);
    } else {
      unawaited(close());
    }
    _onChange();
  }

  void _answer(int code) {
    _channel.write([code]).ignore();
    _closeTimer = Timer(_closeGrace, () => unawaited(close()));
  }

  void _onEnd() {
    if (isActive) {
      _monitor?.finish();
      _problem = BeamProblem.senderLeft;
    }
    unawaited(close());
  }
}
