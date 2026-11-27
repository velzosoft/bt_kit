import 'dart:async';

import 'cancel_token.dart';
import 'exceptions.dart';
import 'log.dart';

/// Runs one native operation at a time, in order.
///
/// Both platforms reject or silently drop a GATT request issued while
/// another is in flight, so every operation on a connection goes through
/// one queue. Each operation has a timeout and can be cancelled; either
/// fails the caller at once, but an operation that has already reached the
/// platform keeps the queue until the platform answers, so the next request
/// never overlaps it. One that never settles releases the queue
/// [settleLimit] after its timeout.
final class OperationQueue {
  OperationQueue({
    this.settleLimit = attTransactionTimeout,
    this._log,
    this.label = '',
  });

  /// Both stacks drop a link whose request has gone unanswered this long,
  /// which fails the request.
  static const attTransactionTimeout = Duration(seconds: 30);

  final Duration settleLimit;

  /// Prefixes log records, such as the peripheral id.
  final String label;
  final BtLog? _log;
  Future<void> _tail = Future.value();
  final _waiting = <_Entry<Object?>>{};

  Future<T> run<T>(
    String name,
    Future<T> Function() operation, {
    required Duration timeout,
    CancelToken? cancelToken,
  }) {
    cancelToken?.throwIfCancelled();
    final entry = _Entry<T>(
      label.isEmpty ? name : '$label: $name',
      operation,
      timeout,
      _log,
    );
    _waiting.add(entry);
    cancelToken?.whenCancelled.then(entry.cancel);
    final previous = _tail;
    _tail = entry.released.future;
    previous.whenComplete(() {
      _waiting.remove(entry);
      entry.start(settleLimit);
    });
    return entry.result.future;
  }

  /// Fails every operation that has not started yet.
  void failWaiting(BluetoothException error) {
    for (final entry in _waiting.toList()) {
      entry.fail(error);
    }
  }
}

final class _Entry<T> {
  _Entry(this.name, this.operation, this.timeout, this.log);

  final String name;
  final Future<T> Function() operation;
  final Duration timeout;
  final BtLog? log;
  final result = Completer<T>();
  final released = Completer<void>();
  final _clock = Stopwatch()..start();
  Duration? _queued;

  void start(Duration settleLimit) {
    if (result.isCompleted) return _release();
    final queued = _queued = _clock.elapsed;
    _clock.reset();
    log?.fine(() => '$name started after ${millis(queued)} in the queue');
    final timeoutTimer = Timer(
      timeout,
      () => fail(OperationTimeoutException(name, timeout)),
    );
    final releaseTimer = Timer(timeout + settleLimit, () {
      log?.warning(
        () =>
            '$name never answered; releasing the queue after '
            '${millis(timeout + settleLimit)}',
      );
      _release();
    });
    Future.sync(operation)
        .then(
          (value) {
            _settled(null);
            if (!result.isCompleted) result.complete(value);
          },
          onError: (Object error, StackTrace stackTrace) {
            _settled(error);
            if (!result.isCompleted) result.completeError(error, stackTrace);
          },
        )
        .whenComplete(() {
          timeoutTimer.cancel();
          releaseTimer.cancel();
          _release();
        });
  }

  void cancel(Object? reason) => fail(OperationCancelledException(reason));

  void fail(BluetoothException error) {
    if (result.isCompleted) return;
    if (_queued case final queued?) {
      log?.warning(
        () =>
            '$name gave up after ${millis(_clock.elapsed)}, having waited '
            '${millis(queued)} in the queue: $error. The queue stays held '
            'until the platform answers',
      );
    }
    result.completeError(error);
  }

  void _settled(Object? error) {
    final took = millis(_clock.elapsed);
    final outcome = error == null ? 'succeeded' : 'failed: $error';
    if (result.isCompleted) {
      log?.warning(() => '$name answered after $took, too late: $outcome');
    } else {
      log?.fine(() => '$name $outcome in $took');
    }
  }

  void _release() {
    if (!released.isCompleted) released.complete();
  }
}
