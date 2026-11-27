import '../models/bond_state.dart';
import '../models/bluetooth_connection_state.dart';
import '../models/disconnect_reason.dart';
import 'peripheral.dart';

/// A change on one peripheral, as reported by `BtKit.events`.
sealed class PeripheralEvent {
  const PeripheralEvent(this.peripheral);

  final Peripheral peripheral;
}

final class ConnectionChanged extends PeripheralEvent {
  const ConnectionChanged(super.peripheral, this.state, [this.reason]);

  final BluetoothConnectionState state;

  /// Set when [state] is [BluetoothConnectionState.disconnected].
  final DisconnectReason? reason;

  @override
  String toString() => 'ConnectionChanged(${peripheral.id}, ${state.name})';
}

final class MtuChanged extends PeripheralEvent {
  const MtuChanged(super.peripheral, this.mtu);

  final int mtu;

  @override
  String toString() => 'MtuChanged(${peripheral.id}, $mtu)';
}

/// The peripheral changed its GATT database; see `Peripheral.servicesChanged`.
final class ServicesChanged extends PeripheralEvent {
  const ServicesChanged(super.peripheral);

  @override
  String toString() => 'ServicesChanged(${peripheral.id})';
}

/// The peripheral's GAP name changed (iOS).
final class NameChanged extends PeripheralEvent {
  const NameChanged(super.peripheral, this.name);

  final String? name;

  @override
  String toString() => 'NameChanged(${peripheral.id}, $name)';
}

/// The bond with the peripheral changed (Android).
final class BondChanged extends PeripheralEvent {
  const BondChanged(super.peripheral, this.state);

  final BondState state;

  @override
  String toString() => 'BondChanged(${peripheral.id}, ${state.name})';
}
