import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

/// How long to wait before each reconnect attempt.
final class Backoff {
  const Backoff([this.delays = standard]);

  /// 1, 2 and 5 s, then 10 s for as long as it takes.
  static const standard = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  final List<Duration> delays;

  /// The wait before retry number [attempt], counting from 0. The last
  /// delay repeats.
  Duration delay(int attempt) => delays[attempt.clamp(0, delays.length - 1)];
}

typedef LinkSession = Future<void> Function(CancelToken cancelToken);

typedef Sleep = Future<void> Function(Duration delay, CancelToken cancelToken);

/// Keeps a link going: runs a [LinkSession] (connect, set up, then stream
/// until the link drops) again and again, waiting [Backoff] delays in
/// between, until [cancel] is called.
///
/// Sessions never overlap. A session that ends normally or with a
/// [BluetoothException] is retried; any other error ends the loop and
/// [run] completes with it.
final class Reconnector {
  Reconnector(
    this._session, {
    this._backoff = const Backoff(),
    this.onRetry,
    this._sleep = cancellableSleep,
  });

  final LinkSession _session;
  final Backoff _backoff;
  final Sleep _sleep;
  final _cancelToken = CancelToken();

  /// Called before each wait, with the error that ended the session, if any.
  final void Function(BluetoothException? error, Duration delay)? onRetry;

  Future<void>? _running;
  var _failures = 0;

  bool get isCancelled => _cancelToken.isCancelled;

  /// Starts the loop, or returns the one already running.
  Future<void> run() => _running ??= _loop();

  /// Call once a session is working, so the next drop waits the shortest
  /// delay again.
  void resetBackoff() => _failures = 0;

  void cancel() => _cancelToken.cancel();

  Future<void> _loop() async {
    while (!isCancelled) {
      BluetoothException? error;
      try {
        await _session(_cancelToken);
      } on BluetoothException catch (e) {
        error = e;
      }
      if (isCancelled) return;
      final delay = _backoff.delay(_failures++);
      onRetry?.call(error, delay);
      await _sleep(delay, _cancelToken);
    }
  }
}

/// Waits for [delay], or less if [cancelToken] is cancelled first.
Future<void> cancellableSleep(Duration delay, CancelToken cancelToken) {
  if (cancelToken.isCancelled) return Future.value();
  final done = Completer<void>();
  final timer = Timer(delay, done.complete);
  unawaited(
    cancelToken.whenCancelled.then((_) {
      timer.cancel();
      if (!done.isCompleted) done.complete();
    }),
  );
  return done.future;
}
