import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'explorer_controller.dart';

/// The live connection state, from `peripheral.connectionStates`, with a
/// Reconnect button once the link is gone.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner(this.explorer, {super.key});

  final ExplorerController explorer;

  @override
  Widget build(BuildContext context) {
    final state = explorer.connection;
    final (label, color) = switch (state) {
      BluetoothConnectionState.connected => ('Connected', RadarColors.sweep),
      BluetoothConnectionState.connecting => ('Connecting…', RadarColors.muted),
      BluetoothConnectionState.disconnecting => (
        'Disconnecting…',
        RadarColors.muted,
      ),
      BluetoothConnectionState.disconnected => (
        _disconnected(explorer.lastDisconnect),
        RadarColors.warm,
      ),
    };
    return Container(
      color: RadarColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox.square(dimension: 10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color),
            ),
          ),
          if (state == BluetoothConnectionState.disconnected)
            TextButton.icon(
              onPressed: () => unawaited(explorer.connect()),
              icon: const Icon(Icons.refresh),
              label: const Text('Reconnect'),
            ),
        ],
      ),
    );
  }

  static String _disconnected(DisconnectReason? reason) =>
      switch (reason?.cause) {
        DisconnectCause.remote => 'Disconnected by the device',
        DisconnectCause.linkLoss => 'Disconnected: out of range',
        DisconnectCause.adapterOff => 'Disconnected: Bluetooth is off',
        DisconnectCause.failedToConnect => 'Could not connect',
        _ => 'Disconnected',
      };
}
