import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/src/platform/channel_backend.dart';

/// A byte channel that records writes and lets tests feed input.
final class FakeByteChannel<N extends Object> implements ByteChannelBackend<N> {
  FakeByteChannel({this.peerId = 'peer'});

  @override
  N get native => throw UnimplementedError('No native object on the host');

  @override
  final String peerId;

  final written = <List<int>>[];
  final _input = StreamController<Uint8List>();
  final _done = Completer<void>();

  bool get isClosed => _done.isCompleted;

  void receive(List<int> bytes) => _input.add(Uint8List.fromList(bytes));

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> write(Uint8List data) async => written.add(data);

  @override
  Future<void> close() async {
    if (_done.isCompleted) return;
    _done.complete();
    await _input.close();
  }
}
