import 'package:meta/meta.dart';

/// An LE physical layer.
enum Phy {
  le1M,

  /// Twice the symbol rate of [le1M]. Check `BluetoothCapabilities.le2MPhy`.
  le2M,

  /// Long range. Check `BluetoothCapabilities.leCodedPhy`.
  leCoded,
}

/// The coding preferred on [Phy.leCoded]: S2 is faster, S8 reaches further.
enum PhyCoding { none, s2, s8 }

/// The PHYs a connection uses in each direction.
@immutable
final class PhyInfo {
  const PhyInfo({required this.tx, required this.rx});

  final Phy tx;
  final Phy rx;

  @override
  bool operator ==(Object other) =>
      other is PhyInfo && other.tx == tx && other.rx == rx;

  @override
  int get hashCode => Object.hash(tx, rx);

  @override
  String toString() => 'PhyInfo(tx: ${tx.name}, rx: ${rx.name})';
}
