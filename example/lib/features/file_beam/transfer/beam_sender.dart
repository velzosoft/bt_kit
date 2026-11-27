import 'dart:async';
import 'dart:math';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../../bluetooth/app_uuids.dart';
import '../protocol/beam_frame.dart';
import '../protocol/beam_link.dart';
import '../protocol/crc32.dart';
import 'beam_payload.dart';
import 'beam_problem.dart';
import 'transfer_monitor.dart';

enum SendPhase { idle, connecting, sending, confirming, delivered, failed }

/// Sends one file to a receiver: connects, reads the PSM, opens the L2CAP
/// channel, streams the frame and waits for the receiver's answer.
final class BeamSender extends ChangeNotifier {
  static const _refresh = Duration(milliseconds: 200);

  var _phase = SendPhase.idle;
  var _step = '';
  BeamPayload? _payload;
  TransferMonitor? _monitor;
  BeamProblem? _problem;
  CancelToken? _cancel;
  Peripheral? _receiver;
  L2capChannel? _channel;
  Timer? _ticker;
  var _disposed = false;

  SendPhase get phase => _phase;

  /// What [SendPhase.connecting] is doing right now.
  String get step => _step;

  BeamPayload? get payload => _payload;

  TransferMonitor? get monitor => _monitor;

  BeamProblem? get problem => _problem;

  bool get isBusy => switch (_phase) {
    SendPhase.connecting || SendPhase.sending || SendPhase.confirming => true,
    _ => false,
  };

  Future<void> send(
    Peripheral receiver,
    Future<BeamPayload> Function() makePayload,
  ) async {
    if (isBusy) return;
    final cancel = _cancel = CancelToken();
    _receiver = receiver;
    _payload = null;
    _monitor = null;
    _problem = null;
    try {
      _connecting('Preparing the file');
      final payload = _payload = await makePayload();
      _connecting('Connecting');
      await receiver.connect(cancelToken: cancel);
      _connecting('Reading the channel number');
      final psm = await _readPsm(receiver, cancel);
      _connecting('Opening the L2CAP channel');
      final channel = _channel = await receiver.openL2capChannel(
        psm,
        secure: BeamLink.secure,
        cancelToken: cancel,
      );
      final answer = _firstByte(channel.input);
      await _stream(channel, payload, cancel);
      _setPhase(SendPhase.confirming);
      final code = await answer.timeout(BeamLink.answerTimeout);
      _finish(code);
    } on Object catch (error) {
      _fail(error, cancelled: cancel.isCancelled);
    } finally {
      _stopTicker();
      await _hangUp();
    }
  }

  void cancel() {
    _cancel?.cancel();
    unawaited(_channel?.close());
  }

  /// Back to choosing a receiver after a delivery or a failure.
  void reset() {
    if (isBusy) return;
    _problem = null;
    _setPhase(SendPhase.idle);
  }

  Future<int> _readPsm(Peripheral receiver, CancelToken cancel) async {
    await receiver.discoverServices(cancelToken: cancel);
    final characteristic = receiver.characteristic(
      AppUuids.fileBeam,
      AppUuids.fileBeamPsm,
    );
    if (characteristic == null) throw const _Refused(BeamProblem.notReceiving);
    final psm = BeamLink.decodePsm(
      await characteristic.read(cancelToken: cancel),
    );
    return psm ?? (throw const _Refused(BeamProblem.notReceiving));
  }

  Future<void> _stream(
    L2capChannel channel,
    BeamPayload payload,
    CancelToken cancel,
  ) async {
    final bytes = payload.bytes;
    final monitor = _monitor = TransferMonitor(bytes.length);
    _setPhase(SendPhase.sending);
    _ticker = Timer.periodic(_refresh, (_) => _notify());
    await channel.write(
      BeamFrame.header(payload.name, bytes.length),
      cancelToken: cancel,
    );
    for (var start = 0; start < bytes.length; start += BeamLink.chunkSize) {
      final end = min(start + BeamLink.chunkSize, bytes.length);
      await channel.write(
        Uint8List.sublistView(bytes, start, end),
        cancelToken: cancel,
      );
      monitor.add(end - start);
    }
    await channel.write(
      BeamFrame.trailer(Crc32.of(bytes)),
      cancelToken: cancel,
    );
    monitor.finish();
  }

  /// The receiver's one-byte answer, or null if the channel closes first.
  static Future<int?> _firstByte(Stream<Uint8List> input) => input
      .firstWhere((chunk) => chunk.isNotEmpty)
      .then<int?>((chunk) => chunk.first, onError: (Object _) => null);

  void _finish(int? code) {
    switch (code) {
      case BeamFrame.ack:
        _setPhase(SendPhase.delivered);
      case BeamFrame.nak:
        _problem = BeamProblem.rejected;
        _setPhase(SendPhase.failed);
      default:
        _problem = BeamProblem.receiverLeft;
        _setPhase(SendPhase.failed);
    }
  }

  void _fail(Object error, {required bool cancelled}) {
    if (cancelled) return _setPhase(SendPhase.idle);
    final midTransfer =
        _phase == SendPhase.sending || _phase == SendPhase.confirming;
    _problem = switch (error) {
      _Refused(:final problem) => problem,
      DisconnectedException() ||
      NativeOperationException() ||
      OperationTimeoutException() when midTransfer => BeamProblem.receiverLeft,
      _ => BeamProblem.of(error),
    };
    _monitor?.finish();
    _setPhase(SendPhase.failed);
  }

  Future<void> _hangUp() async {
    final channel = _channel;
    final receiver = _receiver;
    _channel = null;
    _receiver = null;
    _cancel = null;
    try {
      await channel?.close();
      await receiver?.disconnect();
    } on BluetoothException catch (_) {}
  }

  void _connecting(String step) {
    _step = step;
    _setPhase(SendPhase.connecting);
  }

  void _setPhase(SendPhase phase) {
    _phase = phase;
    _notify();
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    cancel();
    unawaited(_hangUp());
    super.dispose();
  }
}

/// The receiver is reachable but does not offer File beam.
final class _Refused implements Exception {
  const _Refused(this.problem);

  final BeamProblem problem;
}
