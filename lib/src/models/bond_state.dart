/// Whether this device keeps long-term keys for a remote device.
enum BondState {
  none,

  /// Pairing is in progress.
  bonding,
  bonded,
}
