import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:objective_c/objective_c.dart' as objc;

import '../../central/native_types.dart';
import '../../core/exceptions.dart';
import '../../core/native_handle.dart';
import '../../native/ios/bindings.dart';
import '../channel_backend.dart';
import 'ios_peripheral_role.dart';

/// A byte channel on a pair of `NSStream`s, scheduled on the main run loop:
/// the streams of a `CBL2CAPChannel` or an `EASession`.
///
/// Stream delegates are not retained by their streams, and the owner of the
/// streams closes them once nothing references it, so every open channel is
/// kept in [_open], together with [native], until it closes.
final class IosStreamChannel<N extends Object>
    implements ByteChannelBackend<N> {
  IosStreamChannel(this.native, this.peerId, this._input, this._output) {
    _open.add(this);
    for (final stream in <objc.NSStream>[_input, _output]) {
      stream
        ..delegate = _delegate
        ..scheduleInRunLoop(_runLoop, forMode: NSRunLoopCommonModes)
        ..open();
    }
  }

  static final _open = <IosStreamChannel<Object>>{};
  static const _bufferSize = 4096;
  static final _runLoop = objc.NSRunLoop.getMainRunLoop();

  final objc.NSInputStream _input;
  final objc.NSOutputStream _output;
  late final objc.NSStreamDelegate _delegate =
      objc.NSStreamDelegate$Builder.implementAsListener(
        stream_handleEvent_: (_, event) => _handle(event),
      );
  final _readBuffer = malloc<Uint8>(_bufferSize);
  final _writeBuffer = malloc<Uint8>(_bufferSize);
  final _data = StreamController<Uint8List>();
  final _writes = Queue<_Write>();
  final _done = Completer<void>();

  @override
  final N native;

  @override
  final String peerId;

  @override
  Stream<Uint8List> get input => _data.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> write(Uint8List data) {
    if (_done.isCompleted) {
      return Future.error(const DisconnectedException('The channel is closed'));
    }
    final write = _Write(data);
    _writes.add(write);
    _flush();
    return write.done.future;
  }

  @override
  Future<void> close() {
    _close();
    return done;
  }

  void _handle(int event) {
    if (_done.isCompleted) return;
    if (event & objc.NSStreamEvent.NSStreamEventHasBytesAvailable != 0) {
      _read();
    }
    if (event & objc.NSStreamEvent.NSStreamEventHasSpaceAvailable != 0) {
      _flush();
    }
    const ended =
        objc.NSStreamEvent.NSStreamEventEndEncountered |
        objc.NSStreamEvent.NSStreamEventErrorOccurred;
    if (event & ended != 0) _close();
  }

  void _read() {
    while (_input.hasBytesAvailable) {
      final count = _input.read(_readBuffer, maxLength: _bufferSize);
      if (count <= 0) return;
      _data.add(Uint8List.fromList(_readBuffer.asTypedList(count)));
    }
  }

  void _flush() {
    while (_writes.isNotEmpty && _output.hasSpaceAvailable) {
      final write = _writes.first;
      final chunk = min(write.data.length - write.offset, _bufferSize);
      _writeBuffer
          .asTypedList(chunk)
          .setRange(0, chunk, write.data, write.offset);
      final written = _output.write(_writeBuffer, maxLength: chunk);
      if (written < 0) return _close();
      if (written == 0) return;
      write.offset += written;
      if (write.offset == write.data.length) {
        _writes.removeFirst().done.complete();
      }
    }
  }

  void _close() {
    if (_done.isCompleted) return;
    for (final stream in <objc.NSStream>[_input, _output]) {
      stream
        ..delegate = null
        ..removeFromRunLoop(_runLoop, forMode: NSRunLoopCommonModes)
        ..close();
    }
    malloc
      ..free(_readBuffer)
      ..free(_writeBuffer);
    for (final write in _writes) {
      write.done.completeError(
        const DisconnectedException('The channel closed'),
      );
    }
    _writes.clear();
    unawaited(_data.close());
    _done.complete();
    _open.remove(this);
  }
}

/// An L2CAP channel on the streams of a `CBL2CAPChannel`.
final class IosL2capChannel implements L2capChannelBackend {
  IosL2capChannel(CBL2CAPChannel channel, String peerId)
    : psm = channel.PSM,
      _streams = IosStreamChannel(
        channel,
        peerId,
        channel.inputStream,
        channel.outputStream,
      );

  final IosStreamChannel<CBL2CAPChannel> _streams;

  @override
  final int psm;

  @override
  String get peerId => _streams.peerId;

  @override
  L2capChannelHandle get native => IosHandle(_streams.native);

  @override
  Stream<Uint8List> get input => _streams.input;

  @override
  Future<void> get done => _streams.done;

  @override
  Future<void> write(Uint8List data) => _streams.write(data);

  @override
  Future<void> close() => _streams.close();
}

final class _Write {
  _Write(this.data);

  final Uint8List data;
  final done = Completer<void>();
  var offset = 0;
}

/// A PSM published by `CBPeripheralManager`.
final class IosL2capServer implements L2capServerBackend {
  IosL2capServer(this._role, this.psm);

  final IosPeripheralRole _role;
  final _channels = StreamController<L2capChannelBackend>();

  @override
  final int psm;

  @override
  L2capServerHandle get native => IosHandle(_role.manager);

  @override
  Stream<L2capChannelBackend> get channels => _channels.stream;

  void accept(CBL2CAPChannel channel) => _channels.add(
    IosL2capChannel(channel, channel.peer.identifier.UUIDString.toDartString()),
  );

  @override
  Future<void> close() async {
    _role.unpublish(this);
    await _channels.close();
  }
}
