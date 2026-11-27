import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../central/lab_connection.dart';
import '../metrics/soak_metrics.dart';
import '../model/failure_tally.dart';
import '../model/lab_test_id.dart';
import '../model/test_result.dart';
import '../profile/stream_command.dart';
import '../profile/stream_packet.dart';
import 'lab_runner.dart';

/// Notifications at a fixed rate for minutes, checking every sequence
/// number and timing each arrival.
final class NotificationSoakRunner implements LabRunner {
  const NotificationSoakRunner();

  @override
  LabTestId get id => LabTestId.notificationSoak;

  @override
  Future<TestResult> run(LabContext context) async {
    final recorder = TestRecorder(id, context);
    final plan = context.plan;
    final metrics = SoakMetrics(
      rateHz: plan.soakRateHz,
      duration: plan.soakDuration,
    );
    final connection = await context.connect();
    final bool highPriority;
    try {
      highPriority = await connection.requestHighPriority();
      await _Soak(context, connection, metrics).run();
    } finally {
      await quietly(connection.close);
    }
    return recorder.finish(
      summary: metrics.summary,
      checks: metrics.checks(),
      metrics: metrics.toJson(),
      parameters: {
        'rateHz': plan.soakRateHz,
        'seconds': plan.soakDuration.inSeconds,
        'highConnectionPriority': highPriority,
      },
      notes: const [
        'Delay variation is how much later than the fastest value each '
            'value arrived, after removing the drift between the two '
            "phones' clocks, which are not synchronized.",
      ],
    );
  }
}

final class _Soak {
  _Soak(this.context, this.connection, this.metrics);

  static const _drain = Duration(milliseconds: 500);

  final LabContext context;
  final LabConnection connection;
  final SoakMetrics metrics;
  final _clock = Stopwatch();
  final _finished = Completer<void>();

  Future<void> run() async {
    _clock.start();
    final subscription = connection
        .stream(StreamKind.notify)
        .subscribe()
        .listen(_onValue, onError: _onError);
    Timer? end;
    Timer? ticker;
    try {
      await connection.startStream(
        StreamKind.notify,
        metrics.rateHz,
        cancelToken: context.cancelToken,
      );
      final started = _clock.elapsed;
      end = Timer(metrics.duration, () {
        metrics.completed = true;
        _finish();
      });
      ticker = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => context.report(
          metrics.summary,
          (_clock.elapsed - started).inMilliseconds /
              metrics.duration.inMilliseconds,
        ),
      );
      unawaited(context.cancelToken.whenCancelled.then((_) => _finish()));
      await _finished.future;
    } on BluetoothException catch (e) {
      metrics.linkError = FailureTally.describe(e);
    } finally {
      end?.cancel();
      ticker?.cancel();
      await quietly(connection.stopStream);
      await Future<void>.delayed(_drain);
      await subscription.cancel();
    }
  }

  void _onValue(List<int> value) {
    final packet = StreamPacket.decode(value);
    if (packet == null) {
      metrics.malformed++;
    } else {
      metrics.add(packet, arrivalMicros: _clock.elapsedMicroseconds);
    }
  }

  void _onError(Object error) {
    metrics.linkError = FailureTally.describe(error);
    _finish();
  }

  void _finish() {
    if (!_finished.isCompleted) _finished.complete();
  }
}
