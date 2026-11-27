import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/channels/byte_channel.dart' show createL2capChannel;
import 'package:bt_kit/src/platform/channel_backend.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeChannel implements L2capChannelBackend {
  final writes = <List<int>>[];
  final gates = <Completer<void>>[];
  final _input = StreamController<Uint8List>();
  final _done = Completer<void>();

  @override
  int get psm => 0x80;

  @override
  String get peerId => 'peer';

  @override
  L2capChannelHandle get native => throw UnimplementedError();

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> write(Uint8List data) {
    writes.add(data);
    final gate = Completer<void>();
    gates.add(gate);
    return gate.future;
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  void remoteClose() => _done.complete();
}

void main() {
  late FakeChannel backend;
  late L2capChannel channel;

  setUp(() {
    backend = FakeChannel();
    channel = createL2capChannel(backend);
  });

  test('writes reach the platform one at a time, in order', () async {
    final first = channel.write([1]);
    final second = channel.write([2]);
    await pumpEventQueue();
    expect(backend.writes, [
      [1],
    ]);
    backend.gates.first.complete();
    await first;
    await pumpEventQueue();
    expect(backend.writes, [
      [1],
      [2],
    ]);
    backend.gates.last.complete();
    await second;
  });

  test('waiting writes fail once the peer closes the channel', () async {
    unawaited(channel.write([1]));
    final waiting = channel.write([2]);
    await pumpEventQueue();
    backend.remoteClose();
    await expectLater(waiting, throwsA(isA<DisconnectedException>()));
    expect(channel.isOpen, isFalse);
    await expectLater(
      channel.write([3]),
      throwsA(isA<DisconnectedException>()),
    );
  });

  test('a write that times out holds the channel until it finishes', () async {
    await expectLater(
      channel.write([1], timeout: const Duration(milliseconds: 20)),
      throwsA(isA<OperationTimeoutException>()),
    );
    final next = channel.write([2]);
    await pumpEventQueue();
    expect(backend.writes, [
      [1],
    ]);
    backend.gates.first.complete();
    await pumpEventQueue();
    expect(backend.writes.last, [2]);
    backend.gates.last.complete();
    await next;
  });
}
