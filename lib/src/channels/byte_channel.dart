import 'dart:async';
import 'dart:typed_data';

import '../accessories/external_accessories.dart';
import '../central/native_types.dart';
import '../core/bluetooth_uuid.dart';
import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../core/operation_queue.dart';
import '../native/android/bindings.dart' as android;
import '../native/ios/bindings.dart' as ios;
import '../platform/channel_backend.dart';

part 'accessory_session.dart';
part 'l2cap_channel.dart';
part 'rfcomm_channel.dart';

/// A reliable, ordered byte stream to a remote device: an [L2capChannel],
/// an [RfcommChannel] or an [AccessorySession].
///
/// Writes are queued and sent in order. The stream closes when either side
/// closes it or the link drops.
sealed class ByteChannel {
  ByteChannel._(this._backend, BtLog log, String label)
    : _log = log,
      _writes = OperationQueue(log: log, label: label) {
    log.info(() => '$label: open');
    _backend.done.whenComplete(() {
      log.info(() => '$label: closed');
      _open = false;
      _writes.failWaiting(const DisconnectedException('The channel closed'));
    });
  }

  static const writeTimeout = Duration(seconds: 30);

  final ByteChannelBackend<Object> _backend;
  final OperationQueue _writes;
  final BtLog _log;
  var _open = true;

  /// The id of the device at the other end.
  String get peerId => _backend.peerId;

  bool get isOpen => _open;

  /// Received data. Listen once; the stream ends when the channel closes.
  Stream<Uint8List> get input => _backend.input;

  /// Completes when the channel closes, from either side.
  Future<void> get done => _backend.done;

  /// Sends [data] after every earlier write.
  ///
  /// Completes once the platform accepted all of it. A write that times out
  /// or is cancelled after it started is still delivered in order; only the
  /// caller stops waiting.
  Future<void> write(
    List<int> data, {
    Duration timeout = writeTimeout,
    CancelToken? cancelToken,
  }) {
    if (!_open) {
      return Future.error(const DisconnectedException('The channel is closed'));
    }
    final bytes = Uint8List.fromList(data);
    _log.finer(() => '${_writes.label}: write ${hex(bytes)}');
    return _writes.run(
      'write ${bytes.length} bytes',
      () => _backend.write(bytes),
      timeout: timeout,
      cancelToken: cancelToken,
    );
  }

  Future<void> close() {
    _open = false;
    return _backend.close();
  }
}
