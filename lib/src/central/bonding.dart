import 'dart:async';

import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../core/operation_queue.dart';
import '../models/bond_state.dart';
import '../models/permission.dart';
import '../platform/bond_backend.dart';
import 'device_host.dart';

/// Pairing with one remote device, shared by `Peripheral` and
/// `ClassicDevice`. Bond changes are watched while the device is in use and
/// reported through [onChange].
final class Bonding {
  Bonding(this._backend, this._host, this._queue, this._label, {this.onChange});

  static const timeout = Duration(seconds: 60);

  final BondBackend _backend;
  final DeviceHost _host;
  final OperationQueue _queue;
  final String _label;
  final void Function(BondState state)? onChange;
  StreamSubscription<BondState>? _changes;
  var _watchers = 0;

  BondState get state => _backend.bondState;

  Stream<BondState> get states => _backend.bondStates;

  Future<void> create({
    required Duration timeout,
    CancelToken? cancelToken,
  }) async {
    _requireBonding();
    await _host.ensureReady(const {BluetoothPermission.connect});
    if (state == BondState.bonded) return;
    watch();
    try {
      await _queue.run(
        'createBond',
        _backend.createBond,
        timeout: timeout,
        cancelToken: cancelToken,
      );
    } on BluetoothException catch (e) {
      if (e is OperationTimeoutException || e is OperationCancelledException) {
        _cancel();
      }
      rethrow;
    } finally {
      unwatch();
    }
  }

  /// Returns whether the bond is gone once the call completes.
  Future<bool> remove({
    required Duration timeout,
    CancelToken? cancelToken,
  }) async {
    _requireBonding();
    await _host.ensureReady(const {BluetoothPermission.connect});
    if (state == BondState.none) return true;
    if (!_host.capabilities.removeBond) {
      BtLog.bond.warning(
        () =>
            '$_label: apps cannot remove bonds on this Android version; '
            'opening the Bluetooth settings',
      );
      await _host.openBluetoothSettings();
      return state == BondState.none;
    }
    watch();
    try {
      await _queue.run(
        'removeBond',
        _backend.removeBond,
        timeout: timeout,
        cancelToken: cancelToken,
      );
    } finally {
      unwatch();
    }
    return true;
  }

  /// Cancelling is best effort; the caller's own error must not be hidden.
  void _cancel() {
    try {
      _backend.cancelBond();
    } on Object catch (error) {
      BtLog.bond.warning(
        () => '$_label: pairing could not be cancelled',
        error,
      );
    }
  }

  void watch() {
    if (_watchers++ == 0) _changes = _backend.bondStates.listen(_changed);
  }

  void unwatch() {
    if (_watchers == 0 || --_watchers > 0) return;
    unawaited(_changes?.cancel());
    _changes = null;
  }

  void _changed(BondState state) {
    BtLog.bond.info(() => '$_label: ${state.name}');
    onChange?.call(state);
  }

  void _requireBonding() {
    if (!_host.capabilities.bonding) {
      throw const UnsupportedFeatureException(
        'bonding',
        'iOS pairs on its own when the app first uses an encrypted '
            'attribute',
      );
    }
  }
}
