import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bt_kit/bt_kit.dart';

import '../central/lab_connection.dart';
import '../metrics/cancellation_metrics.dart';
import '../model/lab_failure.dart';
import '../profile/reference_profile.dart';

enum BurstKind { readFixed, readLong, writeEcho, readRssi }

enum BurstMode { plain, cancelled, shortTimeout }

/// One operation of a cancellation burst, and how it is disturbed.
final class BurstOperation {
  BurstOperation(
    this.kind,
    this.mode, {
    this.cancelAfter = Duration.zero,
    this.timeout = Timeouts.gatt,
  });

  /// 40% plain, 30% cancelled after 0–30 ms, 30% with a 1–30 ms timeout.
  factory BurstOperation.random(Random random) {
    final kind = BurstKind.values[random.nextInt(BurstKind.values.length)];
    final roll = random.nextInt(10);
    if (roll < 4) return BurstOperation(kind, BurstMode.plain);
    if (roll < 7) {
      return BurstOperation(
        kind,
        BurstMode.cancelled,
        cancelAfter: Duration(
          milliseconds: random.nextInt(maxCancelDelay.inMilliseconds + 1),
        ),
      );
    }
    final span = shortTimeouts.end - shortTimeouts.start;
    return BurstOperation(
      kind,
      BurstMode.shortTimeout,
      timeout: Duration(
        milliseconds: shortTimeouts.start + random.nextInt(span + 1),
      ),
    );
  }

  static const maxCancelDelay = Duration(milliseconds: 30);
  static const shortTimeouts = (start: 1, end: 30);

  /// Past this, an operation counts as stalled: longer than its own
  /// timeout plus the wait behind a burst of others.
  static const settleLimit = Duration(seconds: 30);

  static final _echoValue = utf8.encode('burst write');

  final BurstKind kind;
  final BurstMode mode;
  final Duration cancelAfter;
  final Duration timeout;

  Future<void> run(
    LabConnection connection,
    CancellationMetrics metrics,
  ) async {
    final token = CancelToken();
    Stopwatch? sinceCancel;
    final canceller = mode == BurstMode.cancelled
        ? Timer(cancelAfter, () {
            sinceCancel = Stopwatch()..start();
            token.cancel('Cancelled by the Lab');
          })
        : null;
    try {
      await _perform(connection, token).timeout(settleLimit);
      metrics.add(BurstOutcome.succeeded);
    } on TimeoutException {
      metrics.add(BurstOutcome.stalled);
    } on OperationCancelledException catch (e) {
      metrics.add(BurstOutcome.cancelled);
      if (sinceCancel case final clock?) {
        metrics.addCancelLatency(clock.elapsed);
      } else {
        metrics.failures.add(kind.name, e);
      }
    } on OperationTimeoutException catch (e) {
      metrics.add(BurstOutcome.timedOut);
      if (mode != BurstMode.shortTimeout) {
        metrics
          ..unexpectedTimeouts += 1
          ..failures.add(kind.name, e);
      }
    } on NativeOperationException catch (e) {
      _record(metrics, BurstOutcome.rejected, e);
    } on DisconnectedException catch (e) {
      _record(metrics, BurstOutcome.disconnected, e);
    } on BluetoothException catch (e) {
      _record(metrics, BurstOutcome.failed, e);
    } on ValueMismatch catch (e) {
      _record(metrics, BurstOutcome.crossTalk, e);
    } finally {
      canceller?.cancel();
    }
  }

  void _record(CancellationMetrics metrics, BurstOutcome outcome, Object e) {
    metrics.add(outcome);
    metrics.failures.add(kind.name, e, context: mode.name);
  }

  Future<void> _perform(LabConnection connection, CancelToken token) async {
    switch (kind) {
      case BurstKind.readFixed:
        ValueMismatch.check(
          'Fixed value',
          await connection[ReferenceCharacteristic.fixedValue].read(
            timeout: timeout,
            cancelToken: token,
          ),
          ReferenceProfile.fixedValue,
        );
      case BurstKind.readLong:
        ValueMismatch.check(
          'Long value',
          await connection[ReferenceCharacteristic.longValue].read(
            timeout: timeout,
            cancelToken: token,
          ),
          ReferenceProfile.longValue,
        );
      case BurstKind.writeEcho:
        await connection[ReferenceCharacteristic.echo].write(
          _echoValue,
          timeout: timeout,
          cancelToken: token,
        );
      case BurstKind.readRssi:
        await connection.peripheral.readRssi(
          timeout: timeout,
          cancelToken: token,
        );
    }
  }
}
