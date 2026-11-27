import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:jni/jni.dart';

import '../../core/exceptions.dart';
import '../../native/android/bindings.dart';

/// Reads a socket until it closes.
final class SocketReader {
  SocketReader(BluetoothSocket socket, {required int bufferSize}) {
    _port.listen(_onMessage);
    unawaited(Isolate.spawn(_read, (socket, _port.sendPort, bufferSize)));
  }

  final _port = ReceivePort();
  final _data = StreamController<Uint8List>();
  final _done = Completer<String?>();

  Stream<Uint8List> get data => _data.stream;

  /// Completes when the socket closes, with the error that closed it, if
  /// any.
  Future<String?> get done => _done.future;

  void _onMessage(Object? message) {
    switch (message) {
      case final TransferableTypedData bytes:
        _data.add(bytes.materialize().asUint8List());
      case (final String? error,):
        _port.close();
        unawaited(_data.close());
        _done.complete(error);
    }
  }

  static void _read((BluetoothSocket, SendPort, int) args) {
    final (socket, port, bufferSize) = args;
    final buffer = JByteArray(bufferSize);
    String? error;
    try {
      final input = socket.inputStream!;
      while (true) {
        final count = input.read$1(buffer);
        if (count < 0) break;
        if (count > 0) {
          port.send(
            TransferableTypedData.fromList([buffer.getRange(0, count)]),
          );
        }
      }
    } on JThrowable catch (e) {
      error = e.message;
    }
    port.send((error,));
  }
}

/// Writes to a socket in order, optionally connecting it first.
final class SocketWriter {
  SocketWriter._();

  final _replies = ReceivePort();
  final _ready = Completer<SocketWriter>();
  final _pending = <int, Completer<void>>{};
  SendPort? _commands;
  var _nextId = 0;
  var _stopped = false;

  /// Starts the writer. With [connect], the isolate first runs the blocking
  /// `BluetoothSocket.connect()`; a failure ends in [ConnectionException].
  static Future<SocketWriter> start(
    BluetoothSocket socket, {
    required bool connect,
  }) {
    final writer = SocketWriter._();
    writer._replies.listen(writer._onMessage);
    unawaited(
      Isolate.spawn(_write, (socket, writer._replies.sendPort, connect)),
    );
    return writer._ready.future;
  }

  Future<void> write(Uint8List data) {
    final commands = _commands;
    if (_stopped || commands == null) {
      return Future.error(const DisconnectedException('The channel is closed'));
    }
    final id = _nextId++;
    final written = _pending[id] = Completer<void>();
    commands.send((id, TransferableTypedData.fromList([data])));
    return written.future;
  }

  void stop() {
    if (_stopped) return;
    _stopped = true;
    _commands?.send(null);
    _replies.close();
    for (final pending in _pending.values) {
      pending.completeError(const DisconnectedException('The channel closed'));
    }
    _pending.clear();
  }

  void _onMessage(Object? message) {
    switch (message) {
      case final SendPort commands:
        _commands = commands;
      case (null,):
        _ready.complete(this);
      case (final String error,):
        _stopped = true;
        _replies.close();
        _ready.completeError(
          ConnectionException('The socket did not connect: $error'),
        );
      case (final int id, final String? error):
        final pending = _pending.remove(id);
        if (error == null) {
          pending?.complete();
        } else {
          pending?.completeError(
            NativeOperationException('The socket write failed: $error'),
          );
        }
    }
  }

  static void _write((BluetoothSocket, SendPort, bool) args) {
    final (socket, replies, connect) = args;
    final commands = ReceivePort();
    replies.send(commands.sendPort);
    if (connect) {
      try {
        socket.connect();
      } on JThrowable catch (e) {
        replies.send((e.message,));
        commands.close();
        return;
      }
    }
    replies.send((null,));
    final output = socket.outputStream!;
    commands.listen((command) {
      if (command case (final int id, final TransferableTypedData data)) {
        final bytes = data.materialize().asUint8List();
        final array = JByteArray.of(bytes);
        try {
          output.write$1(array, 0, bytes.length);
          output.flush();
          replies.send((id, null));
        } on JThrowable catch (e) {
          replies.send((id, e.message));
        } finally {
          array.release();
        }
      } else {
        commands.close();
      }
    });
  }
}

/// Accepts incoming sockets until the server socket closes.
///
/// Each accepted socket is handed over through a one-slot Java array that
/// this isolate owns: reading the slot gives this isolate its own reference,
/// independent of the worker that accepted it.
Stream<BluetoothSocket> acceptSockets(BluetoothServerSocket server) {
  final slot = JArray.withLength(BluetoothSocket.type, 1);
  final port = ReceivePort();
  final sockets = StreamController<BluetoothSocket>();
  port.listen((message) {
    switch (message) {
      case final SendPort taken:
        final socket = slot[0];
        slot[0] = null;
        if (socket != null) sockets.add(socket);
        taken.send(null);
      default:
        port.close();
        slot.release();
        unawaited(sockets.close());
    }
  });
  unawaited(Isolate.spawn(_accept, (server, slot, port.sendPort)));
  return sockets.stream;
}

Future<void> _accept(
  (BluetoothServerSocket, JArray<BluetoothSocket?>, SendPort) args,
) async {
  final (server, slot, port) = args;
  final taken = ReceivePort();
  final acknowledgements = StreamIterator(taken);
  try {
    while (true) {
      final socket = server.accept();
      if (socket == null) break;
      slot[0] = socket;
      socket.release();
      port.send(taken.sendPort);
      await acknowledgements.moveNext();
    }
  } on JThrowable catch (_) {}
  taken.close();
  port.send(null);
}
