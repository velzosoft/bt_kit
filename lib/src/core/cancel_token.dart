import 'dart:async';

import 'exceptions.dart';

/// Cancels one or more pending operations.
///
/// ```dart
/// final token = CancelToken();
/// final value = characteristic.read(cancelToken: token);
/// token.cancel();
/// ```
final class CancelToken {
  final _cancelled = Completer<Object?>();

  bool get isCancelled => _cancelled.isCompleted;

  /// Completes with the cancellation reason once [cancel] is called.
  Future<Object?> get whenCancelled => _cancelled.future;

  void cancel([Object? reason]) {
    if (!_cancelled.isCompleted) _cancelled.complete(reason);
  }

  void throwIfCancelled() {
    if (isCancelled) throw const OperationCancelledException();
  }
}
