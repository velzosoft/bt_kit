import 'dart:async';

import '../core/exceptions.dart';

/// The platform request of a connection that is waiting for its callback.
///
/// Operations are serialized, so at most one request is pending. Callbacks
/// that do not match it, such as the late answer to a request that timed
/// out, are ignored.
final class RequestSlot {
  PendingRequest<Object?>? _pending;

  bool get isBusy => _pending != null;

  /// Starts a request; a request still pending is superseded and fails.
  PendingRequest<T> begin<T>(Object kind, {Object? key}) {
    _pending?.fail(
      const NativeOperationException('Superseded by a new request'),
    );
    final request = PendingRequest<T>._(this, kind, key);
    _pending = request;
    return request;
  }

  /// Completes the pending request if it matches; returns whether it did.
  bool complete(Object kind, Object? value, {Object? key}) {
    final request = _match(kind, key);
    request?._complete(value);
    return request != null;
  }

  bool fail(Object kind, BluetoothException error, {Object? key}) {
    final request = _match(kind, key);
    request?.fail(error);
    return request != null;
  }

  void failAny(BluetoothException error) => _pending?.fail(error);

  PendingRequest<Object?>? _match(Object kind, Object? key) {
    final request = _pending;
    if (request == null || request.kind != kind) return null;
    if (key != null && request.key != null && key != request.key) return null;
    return request;
  }
}

/// A request issued to the platform and settled by its callback.
final class PendingRequest<T> {
  PendingRequest._(this._slot, this.kind, this.key);

  final RequestSlot _slot;
  final Object kind;
  final Object? key;
  final _completer = Completer<T>();

  Future<T> get future => _completer.future;

  /// Whether the request still waits for its callback.
  bool get isPending => identical(_slot._pending, this);

  /// Fails this request if it is still pending, and only this request.
  void fail(BluetoothException error) {
    if (!isPending) return;
    _slot._pending = null;
    _completer.completeError(error);
  }

  void _complete(Object? value) {
    if (!isPending) return;
    _slot._pending = null;
    _completer.complete(value as T);
  }
}
