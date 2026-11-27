import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../central/native_types.dart';
import '../../core/native_handle.dart';
import '../../native/android/bindings.dart';
import '../channel_backend.dart';
import 'jni_conversions.dart';
import 'socket_io.dart';

/// A connected `BluetoothSocket`, L2CAP or RFCOMM. Its blocking streams are
/// read and written on background isolates.
///
/// The workers use the socket this isolate owns, so every open channel is
/// kept in [_open] until it closes, even if the app drops it.
final class AndroidSocketChannel implements RfcommChannelBackend {
  AndroidSocketChannel._(this.native, this.peerId, this._writer)
    : _reader = SocketReader(
        native,
        bufferSize: max(4096, native.maxReceivePacketSize),
      ) {
    _open.add(this);
    _reader.done.whenComplete(_closed);
  }

  static final _open = <AndroidSocketChannel>{};

  /// Connects [socket] on a worker isolate; closes it if that fails.
  static Future<AndroidSocketChannel> connect(
    BluetoothSocket socket,
    String peerId,
  ) async {
    try {
      final writer = await SocketWriter.start(socket, connect: true);
      return AndroidSocketChannel._(socket, peerId, writer);
    } on Object {
      guardJni('Closing a socket', socket.close);
      rethrow;
    }
  }

  /// Wraps a socket a server accepted.
  static Future<AndroidSocketChannel> accepted(BluetoothSocket socket) async {
    final peerId = takeString(socket.remoteDevice?.address) ?? '';
    final writer = await SocketWriter.start(socket, connect: false);
    return AndroidSocketChannel._(socket, peerId, writer);
  }

  final SocketReader _reader;
  final SocketWriter _writer;
  final _done = Completer<void>();

  @override
  final BluetoothSocket native;

  @override
  final String peerId;

  @override
  Stream<Uint8List> get input => _reader.data;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> write(Uint8List data) => _writer.write(data);

  /// Closing the socket ends the reader's blocking read.
  @override
  Future<void> close() {
    _closed();
    return done;
  }

  void _closed() {
    if (_done.isCompleted) return;
    _writer.stop();
    guardJni('Closing a socket', native.close);
    _done.complete();
    _open.remove(this);
  }
}

/// An L2CAP channel on a [AndroidSocketChannel].
final class AndroidL2capChannel implements L2capChannelBackend {
  AndroidL2capChannel._(this._socket, this.psm);

  /// Connects to [psm] on [device].
  static Future<AndroidL2capChannel> connect(
    BluetoothDevice device,
    String id,
    int psm, {
    required bool secure,
  }) async {
    final socket = guardJni(
      'Creating an L2CAP channel',
      () => secure
          ? device.createL2capChannel(psm)
          : device.createInsecureL2capChannel(psm),
    );
    return AndroidL2capChannel._(
      await AndroidSocketChannel.connect(socket, id),
      psm,
    );
  }

  final AndroidSocketChannel _socket;

  @override
  final int psm;

  @override
  String get peerId => _socket.peerId;

  @override
  L2capChannelHandle get native => AndroidHandle(_socket.native);

  @override
  Stream<Uint8List> get input => _socket.input;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> write(Uint8List data) => _socket.write(data);

  @override
  Future<void> close() => _socket.close();
}

/// A `BluetoothServerSocket` accepting on a background isolate, kept in
/// [_open] until closed, like channels.
final class AndroidServerSocket {
  AndroidServerSocket(this.native) {
    _open.add(this);
  }

  static final _open = <AndroidServerSocket>{};

  final BluetoothServerSocket native;

  late final Stream<AndroidSocketChannel> channels = acceptSockets(native)
      .asyncMap(AndroidSocketChannel.accepted);

  Future<void> close() async {
    guardJni('Closing a server socket', native.close);
    _open.remove(this);
  }
}

/// A published L2CAP PSM.
final class AndroidL2capServer implements L2capServerBackend {
  AndroidL2capServer(BluetoothServerSocket socket)
    : _server = AndroidServerSocket(socket),
      psm = socket.psm;

  final AndroidServerSocket _server;

  @override
  final int psm;

  @override
  L2capServerHandle get native => AndroidHandle(_server.native);

  @override
  late final Stream<L2capChannelBackend> channels = _server.channels.map(
    (socket) => AndroidL2capChannel._(socket, psm),
  );

  @override
  Future<void> close() => _server.close();
}

/// A listening RFCOMM service.
final class AndroidRfcommServer implements RfcommServerBackend {
  AndroidRfcommServer(BluetoothServerSocket socket)
    : _server = AndroidServerSocket(socket);

  final AndroidServerSocket _server;

  @override
  BluetoothServerSocket get native => _server.native;

  @override
  Stream<RfcommChannelBackend> get channels => _server.channels;

  @override
  Future<void> close() => _server.close();
}
