import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../../../bluetooth/scanner.dart';
import '../central/lab_connection.dart';
import '../central/lab_target.dart';
import '../model/failure_tally.dart';
import '../model/lab_plan.dart';
import '../model/lab_test_id.dart';
import '../model/test_progress.dart';
import '../model/test_result.dart';

/// One Lab test. Runners are plain Dart, so the Lab screen and the
/// integration tests share them.
abstract interface class LabRunner {
  LabTestId get id;

  Future<TestResult> run(LabContext context);
}

/// What a runner works with: the plan, the reference peripheral, a
/// cancellation token and a place for live progress.
final class LabContext {
  LabContext({
    required this.plan,
    required this.cancelToken,
    required this.onProgress,
    this.target,
    this.scanner,
  });

  final LabPlan plan;
  final LabTarget? target;

  /// The app's shared scan, when the Lab runs inside the app.
  final Scanner? scanner;
  final CancelToken cancelToken;
  final void Function(TestProgress progress) onProgress;

  bool get isCancelled => cancelToken.isCancelled;

  LabTarget get reference =>
      target ?? (throw StateError('This test needs a reference peripheral'));

  void report(String summary, [double? fraction]) =>
      onProgress(TestProgress(summary, fraction: fraction?.clamp(0.0, 1.0)));

  /// Connects to the reference, requesting [mtu] if given, and discovers
  /// its profile. If the first attempt fails, the reference may have
  /// changed its address: it is found again by its service and tried once
  /// more. A link that drops while connecting is tried once more too:
  /// Android may still have been closing the previous link to the
  /// reference, and closes the new one with it.
  Future<LabConnection> connect({int? mtu}) async {
    try {
      return await _open(mtu);
    } on DisconnectedException {
      if (isCancelled) rethrow;
      await pause(const Duration(seconds: 1));
      return _open(mtu);
    } on BluetoothException catch (e) {
      final unreachable =
          e is ConnectionException || e is OperationTimeoutException;
      if (isCancelled || !unreachable || !await reference.relocate()) rethrow;
      return _open(mtu);
    }
  }

  Future<LabConnection> _open(int? mtu) => LabConnection.open(
    reference.peripheral,
    timeout: plan.connectTimeout,
    mtu: mtu,
    cancelToken: cancelToken,
  );

  /// Runs [body] with the app's shared scan paused, so that it can scan
  /// with options of its own.
  Future<T> withOwnScans<T>(Future<T> Function() body) async {
    scanner?.pause();
    try {
      return await body();
    } finally {
      scanner?.resume();
    }
  }

  /// Waits for [duration], or less if the run is cancelled.
  Future<void> pause(Duration duration) => Future.any<Object?>([
    Future<void>.delayed(duration),
    cancelToken.whenCancelled,
  ]);
}

/// Times a test and assembles its [TestResult].
final class TestRecorder {
  TestRecorder(this.id, this.context) : startedAt = DateTime.now();

  final LabTestId id;
  final LabContext context;
  final DateTime startedAt;

  TestResult finish({
    required String summary,
    required List<Check> checks,
    Map<String, Object?> metrics = const {},
    Map<String, Object?> parameters = const {},
    FailureTally? failures,
    List<String> notes = const [],
  }) => TestResult(
    id: id,
    criterion: id.criterion(context.plan),
    startedAt: startedAt,
    finishedAt: DateTime.now(),
    summary: summary,
    parameters: parameters,
    checks: checks,
    metrics: metrics,
    failures: failures,
    notes: notes,
    cancelled: context.isCancelled,
  );
}

/// Runs [action], ignoring a Bluetooth failure: for clean-up that must
/// not hide the error that made it necessary.
Future<void> quietly(Future<void> Function() action) async {
  try {
    await action();
  } on BluetoothException catch (_) {}
}
