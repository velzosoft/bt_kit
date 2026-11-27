import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import '../central/lab_connection.dart';
import '../metrics/sequence_tracker.dart';
import '../model/lab_failure.dart';
import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import '../profile/reference_profile.dart';
import '../profile/stream_command.dart';
import '../profile/stream_packet.dart';
import 'flow_steps.dart';
import 'lab_runner.dart';

/// Every characteristic of the reference profile once: reads, writes with
/// and without response, long values, notifications, indications, ATT
/// errors, pairing, RSSI and MTU.
final class GattFlowsRunner implements LabRunner {
  const GattFlowsRunner();

  @override
  LabTestId get id => LabTestId.gattFlows;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final pairing = context.plan.includePairing;
    final steps = FlowSteps(context, total: pairing ? 12 : 11);
    final metrics = <String, Object?>{};
    final connection = await context.connect();
    try {
      await _Flows(connection, steps, metrics).run(pairing: pairing);
    } finally {
      await quietly(connection.close);
    }
    return recorder.finish(
      summary: steps.summary,
      checks: steps.checks,
      metrics: metrics,
      failures: steps.failures,
      notes: [
        if (!pairing)
          'Encrypted read skipped; turn on "Include pairing" to test it.',
      ],
    );
  }
}

final class _Flows {
  _Flows(this.connection, this.steps, this.metrics);

  final LabConnection connection;
  final FlowSteps steps;
  final Map<String, Object?> metrics;

  Peripheral get _peripheral => connection.peripheral;

  CancelToken get _cancel => steps.context.cancelToken;

  Future<void> run({required bool pairing}) async {
    await steps.step('Read the Info value', _info);
    await steps.step('Read a fixed value', _fixed);
    await steps.step(
      'Write and read back',
      () => _echo(_payload(20, seed: 1), withResponse: true),
    );
    await steps.step(
      'Write without response',
      () => _echo(
        _payload(
          math.min(20, _peripheral.maximumWriteLength(withResponse: false)),
          seed: 2,
        ),
        withResponse: false,
      ),
    );
    await steps.step(
      'Long write',
      () => _echo(
        _payload(math.min(300, _peripheral.maximumWriteLength()), seed: 3),
        withResponse: true,
      ),
    );
    await steps.step('Long read', _longRead);
    await steps.step(
      'Notifications',
      () => _stream(StreamKind.notify, count: 20, rateHz: 20),
    );
    await steps.step(
      'Indications',
      () => _stream(StreamKind.indicate, count: 10, rateHz: 10),
    );
    await steps.step(
      'ATT error from the peripheral',
      () => _fault(GattError.readNotPermitted),
    );
    if (pairing) await steps.step('Encrypted read', _encrypted);
    await steps.step('Read RSSI', _rssi);
    await steps.step('MTU', _mtu);
  }

  Future<String> _info() async {
    final info = await connection.readInfo();
    metrics['reference'] = info;
    return info;
  }

  Future<String> _fixed() async {
    final value = await connection[ReferenceCharacteristic.fixedValue].read(
      cancelToken: _cancel,
    );
    ValueMismatch.check('Fixed value', value, ReferenceProfile.fixedValue);
    return '${value.length} bytes';
  }

  Future<String> _echo(Uint8List payload, {required bool withResponse}) async {
    final echo = connection[ReferenceCharacteristic.echo];
    await echo.write(payload, withResponse: withResponse, cancelToken: _cancel);
    ValueMismatch.check('Echo', await echo.read(cancelToken: _cancel), payload);
    return '${payload.length} bytes';
  }

  Future<String> _longRead() async {
    final value = await connection[ReferenceCharacteristic.longValue].read(
      cancelToken: _cancel,
    );
    ValueMismatch.check('Long value', value, ReferenceProfile.longValue);
    return '${value.length} bytes';
  }

  Future<String> _stream(
    StreamKind kind, {
    required int count,
    required int rateHz,
  }) async {
    final sequence = SequenceTracker();
    var malformed = 0;
    final enough = Completer<void>();
    final subscription = connection
        .stream(kind)
        .subscribe()
        .listen(
          (value) {
            final packet = StreamPacket.decode(value);
            if (packet == null) {
              malformed++;
            } else {
              sequence.add(packet.sequence);
            }
            if (sequence.received >= count && !enough.isCompleted) {
              enough.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!enough.isCompleted) enough.completeError(error, stackTrace);
          },
        );
    final limit =
        Duration(milliseconds: count * 1000 ~/ rateHz) +
        const Duration(seconds: 5);
    try {
      await connection.startStream(kind, rateHz, cancelToken: _cancel);
      await enough.future.timeout(
        limit,
        onTimeout: () => throw DeadlineExceeded(
          '${sequence.received} of $count ${kind.name} values within '
          '${limit.inSeconds} s',
        ),
      );
    } finally {
      await quietly(connection.stopStream);
      await subscription.cancel();
    }
    if (!sequence.isClean || malformed > 0) {
      throw UnexpectedResult(
        '${sequence.lost} lost, ${sequence.outOfOrder} out of order, '
        '${sequence.duplicates} repeated, $malformed malformed',
      );
    }
    return '$count values in order';
  }

  Future<String> _fault(GattError fault) async {
    final target = connection[ReferenceCharacteristic.faultTarget];
    await connection.setFault(fault);
    GattError? received;
    try {
      await target.read(cancelToken: _cancel);
    } on GattException catch (e) {
      received = e.error;
    } finally {
      await quietly(() => connection.setFault(null));
    }
    if (received != fault) {
      throw UnexpectedResult(
        'Expected ${fault.name}, got ${received?.name ?? 'a value'}',
      );
    }
    ValueMismatch.check(
      'Fault target after clearing',
      await target.read(cancelToken: _cancel),
      ReferenceProfile.faultTargetValue,
    );
    return '${fault.name}, then the value once cleared';
  }

  Future<String> _encrypted() async {
    final value = await connection[ReferenceCharacteristic.encrypted].read(
      timeout: const Duration(seconds: 30),
      cancelToken: _cancel,
    );
    ValueMismatch.check(
      'Encrypted value',
      value,
      ReferenceProfile.encryptedValue,
    );
    return 'read over an encrypted link';
  }

  Future<String> _rssi() async {
    final rssi = await _peripheral.readRssi(cancelToken: _cancel);
    metrics['rssi'] = rssi;
    return '$rssi dBm';
  }

  Future<String> _mtu() async {
    if (!BtKit.instance.capabilities.requestMtu) {
      final length = _peripheral.maximumWriteLength(withResponse: false);
      metrics['maximumWriteWithoutResponse'] = length;
      return 'negotiated by the system; $length bytes per write';
    }
    final mtu = await _peripheral.requestMtu(247, cancelToken: _cancel);
    metrics['mtu'] = mtu;
    if (mtu < 23) throw UnexpectedResult('MTU $mtu is below the minimum 23');
    return 'MTU $mtu';
  }

  static Uint8List _payload(int length, {required int seed}) =>
      Uint8List.fromList([
        for (var i = 0; i < length; i++) (i * 31 + seed) & 0xff,
      ]);
}
