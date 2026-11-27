// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/channels/byte_channel.dart' show createL2capChannel;
import 'package:bt_kit/src/platform/channel_backend.dart';
import 'package:bt_radar/features/file_beam/protocol/beam_frame.dart';
import 'package:bt_radar/features/file_beam/protocol/crc32.dart';
import 'package:bt_radar/features/file_beam/transfer/beam_problem.dart';
import 'package:bt_radar/features/file_beam/transfer/beam_reception.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeChannel implements L2capChannelBackend {
  final written = <int>[];
  final _input = StreamController<Uint8List>();
  final _done = Completer<void>();

  bool get isClosed => _done.isCompleted;

  void receive(List<int> bytes) => _input.add(Uint8List.fromList(bytes));

  Future<void> remoteClose() => _input.close();

  @override
  int get psm => 0x80;

  @override
  String get peerId => 'sender';

  @override
  L2capChannelHandle get native => throw UnimplementedError();

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> write(Uint8List data) async => written.addAll(data);

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }
}

Uint8List frame(String name, List<int> payload, {int? crc}) =>
    Uint8List.fromList([
      ...BeamFrame.header(name, payload.length),
      ...payload,
      ...BeamFrame.trailer(crc ?? Crc32.of(payload)),
    ]);

void main() {
  final random = Random(3);
  final payload = List.generate(20000, (_) => random.nextInt(256));
  late FakeChannel channel;
  late BeamReception reception;
  var changes = 0;

  setUp(() {
    changes = 0;
    channel = FakeChannel();
    reception = BeamReception(createL2capChannel(channel), () => changes++);
  });

  tearDown(() => reception.close());

  Future<void> receiveInChunks(List<int> bytes, int size) async {
    for (var i = 0; i < bytes.length; i += size) {
      channel.receive(bytes.sublist(i, min(i + size, bytes.length)));
      await pumpEventQueue();
    }
  }

  test('receives a file, measures it and acknowledges it', () async {
    expect(reception.stage, ReceptionStage.connected);
    final bytes = frame('test.bin', payload);
    await receiveInChunks(bytes.sublist(0, 3000), 1000);
    expect(reception.stage, ReceptionStage.receiving);
    expect(reception.header?.name, 'test.bin');
    expect(reception.monitor?.total, payload.length);
    expect(reception.monitor?.transferred, 3000 - 22);

    await receiveInChunks(bytes.sublist(3000), 777);
    expect(reception.stage, ReceptionStage.received);
    expect(reception.file?.bytes, payload);
    expect(reception.file?.isPng, isFalse);
    expect(channel.written, [BeamFrame.ack]);
    expect(changes, greaterThanOrEqualTo(2));
  });

  test('answers a damaged file with NAK and keeps nothing', () async {
    final bytes = frame('test.bin', payload)..[500] ^= 0xff;
    await receiveInChunks(bytes, 4096);
    expect(reception.stage, ReceptionStage.failed);
    expect(reception.file, isNull);
    expect(reception.problem?.title, 'Checksum failed');
    expect(channel.written, [BeamFrame.nak]);
  });

  test('reports a sender that walks away mid-transfer', () async {
    final bytes = frame('test.bin', payload);
    await receiveInChunks(bytes.sublist(0, bytes.length ~/ 2), 4096);
    await channel.remoteClose();
    await pumpEventQueue();
    expect(reception.stage, ReceptionStage.failed);
    expect(reception.problem, BeamProblem.senderLeft);
    expect(reception.isClosed, isTrue);
    expect(channel.isClosed, isTrue);
  });

  test('closes the channel on data that is not a beam', () async {
    channel.receive('GET / HTTP/1.1'.codeUnits);
    await pumpEventQueue();
    expect(reception.stage, ReceptionStage.failed);
    expect(reception.problem?.title, 'Not a File beam transfer');
    expect(channel.written, isEmpty);
    expect(channel.isClosed, isTrue);
  });

  test('recognizes a received PNG', () async {
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3];
    await receiveInChunks(frame('card.png', png), 5);
    expect(reception.file?.isPng, isTrue);
  });
}
