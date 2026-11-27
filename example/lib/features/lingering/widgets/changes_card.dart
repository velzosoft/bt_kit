import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../lingering_watch.dart';

/// How often the surroundings changed, and whether the watch is running.
class ChangesCard extends StatelessWidget {
  const ChangesCard({
    super.key,
    required this.watch,
    required this.devicesAround,
  });

  final LingeringWatch watch;
  final int devicesAround;

  String get _status {
    if (!watch.isWatching) {
      return 'Getting started. The first look is a few seconds away.';
    }
    final minutes = DateTime.now().difference(watch.startedAt).inMinutes;
    final watching = minutes < 1
        ? 'Watching for less than a minute'
        : 'Watching for $minutes min';
    return '$watching · $devicesAround around you · a look every '
        '${LingeringWatch.interval.inSeconds} s';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final changes = watch.churnEvents;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Your surroundings changed ',
                    style: text.titleMedium,
                  ),
                  TextSpan(
                    text: '$changes',
                    style: text.displaySmall?.copyWith(
                      color: RadarColors.sweep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: changes == 1 ? ' time' : ' times',
                    style: text.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: text.bodySmall?.copyWith(color: RadarColors.muted),
            ),
            const SizedBox(height: 12),
            Text(
              'Keep this screen open while you move around: into another '
              'room, onto a bus, into a shop.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
