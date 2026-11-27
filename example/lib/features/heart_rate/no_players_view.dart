import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'showdown.dart';

/// The showdown before anyone has joined.
class NoPlayersView extends StatelessWidget {
  const NoPlayersView({super.key, required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.monitor_heart_outlined,
              size: 56,
              color: RadarColors.warm,
            ),
            const SizedBox(height: 16),
            Text(
              'Who keeps their cool?',
              style: text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add up to ${Showdown.maxPlayers} people wearing heart-rate '
              'sensors and watch their pulse live, ranked, with a panic meter '
              'against their own first minute.',
              style: text.bodyMedium?.copyWith(color: RadarColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add),
              label: const Text('Add player'),
            ),
            const SizedBox(height: 24),
            const SupportedHardwareNote(),
          ],
        ),
      ),
    );
  }
}

class SupportedHardwareNote extends StatelessWidget {
  const SupportedHardwareNote({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Works with heart-rate chest straps, and with watches that have a '
    'heart-rate broadcast mode (turn it on first). Apple Watch does not '
    'broadcast heart rate on its own.',
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: RadarColors.muted),
    textAlign: TextAlign.center,
  );
}
