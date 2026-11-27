import 'dart:async';

import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../models/bond_state.dart';
import '../../native/android/bindings.dart';
import '../bond_backend.dart';
import 'android_broadcasts.dart';
import 'android_companion.dart';
import 'jni_conversions.dart';

/// Bond changes of every device, from `ACTION_BOND_STATE_CHANGED`.
final class AndroidBonds {
  AndroidBonds(Context context)
    : _changes = androidBroadcasts(context, [
        BluetoothDevice.ACTION_BOND_STATE_CHANGED,
      ], _parse);

  final Stream<(String, BondState)> _changes;

  Stream<BondState> states(String address) => _changes
      .where((change) => change.$1 == address)
      .map((change) => change.$2);

  static (String, BondState)? _parse(Intent intent) {
    final address = addressExtra(intent);
    final state = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1);
    if (address == null || state < 0) return null;
    return (address, bondStateOf(state));
  }
}

BondState bondStateOf(int state) => switch (state) {
  BluetoothDevice.BOND_BONDED => BondState.bonded,
  BluetoothDevice.BOND_BONDING => BondState.bonding,
  _ => BondState.none,
};

/// Bonding with one device, built on `BluetoothDevice.createBond` and
/// `CompanionDeviceManager.removeBond`.
///
/// Android reports the outcome of both only through
/// `ACTION_BOND_STATE_CHANGED`, so each call waits for the matching change.
final class AndroidBond implements BondBackend {
  AndroidBond(this._bonds, this._companion, this._device, this._id);

  final AndroidBonds _bonds;
  final AndroidCompanion _companion;
  final BluetoothDevice _device;
  final String _id;

  @override
  BondState get bondState =>
      guardJni('Reading the bond state', () => bondStateOf(_device.bondState));

  @override
  Stream<BondState> get bondStates => _bonds.states(_id);

  @override
  Future<void> createBond() async {
    final ended = _StateWait(bondStates, (s) => s != BondState.bonding);
    try {
      if (bondState != BondState.bonding) {
        final started = guardJni('Bonding', _device.createBond);
        if (!started) {
          if (bondState == BondState.bonded) return;
          throw const BondException('Android refused to start pairing');
        }
      }
      if (await ended.future != BondState.bonded) {
        throw const BondException('Pairing failed or was rejected');
      }
    } finally {
      ended.cancel();
    }
  }

  /// `cancelBondProcess` is public from API 37; before, it is a system API.
  /// It still needs `BLUETOOTH_PRIVILEGED` for a pairing this app did not
  /// start, so a refusal only leaves the pairing to finish on its own.
  @override
  void cancelBond() {
    if (Build$VERSION.SDK_INT < _cancelApi) return;
    try {
      guardJni('Cancelling pairing', () => _device.cancelBondProcess());
    } on BluetoothException catch (error) {
      BtLog.bond.warning(() => '$_id: pairing could not be cancelled', error);
    }
  }

  static const _cancelApi = 37;

  @override
  Future<void> removeBond() async {
    final associationId = await _companion.associationFor(_id);
    final gone = _StateWait(bondStates, (s) => s == BondState.none);
    try {
      if (!_companion.removeBond(associationId)) {
        if (bondState == BondState.none) return;
        throw const BondException(
          'CompanionDeviceManager refused to remove the bond',
        );
      }
      await gone.future;
    } finally {
      gone.cancel();
    }
  }
}

/// Waits for the first state from [states] that passes [test], listening
/// from construction so that no change is missed.
final class _StateWait {
  _StateWait(Stream<BondState> states, bool Function(BondState) test) {
    _subscription = states.listen((state) {
      if (test(state) && !_result.isCompleted) _result.complete(state);
    });
  }

  final _result = Completer<BondState>();
  late final StreamSubscription<BondState> _subscription;

  Future<BondState> get future => _result.future;

  void cancel() => unawaited(_subscription.cancel());
}
