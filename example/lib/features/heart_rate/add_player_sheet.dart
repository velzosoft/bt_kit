import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/bluetooth_state_panel.dart';
import '../../app/theme.dart';
import '../../bluetooth/tracked_device.dart';
import '../../widgets/kind_style.dart';
import 'no_players_view.dart';
import 'showdown.dart';

Future<void> showAddPlayerSheet(BuildContext context, Showdown showdown) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddPlayerSheet(showdown: showdown),
    );

/// Heart-rate sensors nearby, from the app's shared scan. One tap adds a
/// player; the sheet stays open for the next one.
class AddPlayerSheet extends StatelessWidget {
  const AddPlayerSheet({super.key, required this.showdown});

  final Showdown showdown;

  void _add(BuildContext context, TrackedDevice device) {
    showdown.add(device);
    if (showdown.isFull) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = AppScope.of(context).scanner;
    final text = Theme.of(context).textTheme;
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: ListenableBuilder(
        listenable: Listenable.merge([scanner, showdown]),
        builder: (context, _) {
          if (BluetoothStatePanel.needed(scanner.status)) {
            return BluetoothStatePanel(scanner: scanner);
          }
          final sensors = showdown.candidates(scanner.bySignal);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add a player', style: text.titleMedium),
                    Text(
                      '${showdown.players.length} of ${Showdown.maxPlayers} '
                      'players · tap a sensor to add it',
                      style: text.bodySmall?.copyWith(color: RadarColors.muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: sensors.isEmpty
                    ? const _Searching()
                    : ListView(
                        children: [
                          for (final device in sensors)
                            _SensorTile(
                              device,
                              onTap: () => _add(context, device),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SensorTile extends StatelessWidget {
  const _SensorTile(this.device, {required this.onTap});

  final TrackedDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: KindAvatar(device.kind),
    title: Text(device.displayName),
    subtitle: Text('${device.proximity.label} · ${device.rssi.round()} dBm'),
    trailing: const Icon(Icons.person_add_alt),
  );
}

class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text('Looking for heart-rate sensors…', style: text.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Put the strap on: most only advertise while they touch skin. '
            'A sensor already connected to another app or phone may not '
            'show up.',
            style: text.bodySmall?.copyWith(color: RadarColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const SupportedHardwareNote(),
        ],
      ),
    );
  }
}
