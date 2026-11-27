import '../models/bond_state.dart';

/// Bonding with one remote device.
abstract interface class BondBackend {
  BondState get bondState;

  /// Changes of [bondState]; the platform watches for them while listened.
  Stream<BondState> get bondStates;

  /// Starts pairing, or joins one in progress, and completes once bonded.
  /// Fails with `BondException` when it ends without a bond.
  Future<void> createBond();

  /// Stops pairing in progress.
  void cancelBond();

  /// Removes the bond and completes once it is gone. Only called where
  /// `BluetoothCapabilities.removeBond` holds.
  Future<void> removeBond();
}
