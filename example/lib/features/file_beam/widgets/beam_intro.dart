import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';

/// How File beam works, shown until the user picks a role.
class BeamIntro extends StatelessWidget {
  const BeamIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.send_to_mobile, size: 72, color: RadarColors.sweep),
        const SizedBox(height: 16),
        Text(
          'Send a picture to a nearby phone, Android or iPhone, with no '
          'internet.',
          textAlign: TextAlign.center,
          style: text.titleMedium,
        ),
        const SizedBox(height: 24),
        const _Step(1, 'On the other phone, open File beam and tap Receive.'),
        const _Step(2, 'On this phone, tap Send and pick that phone.'),
        const _Step(
          3,
          'Watch the speed: the file streams over a Bluetooth L2CAP '
          'channel, much faster than regular Bluetooth LE messages.',
        ),
        const SizedBox(height: 16),
        Text(
          'The receiver shares its channel number in a GATT characteristic '
          'and advertises it. Each file ends with a checksum, so a damaged '
          'copy is never shown.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: RadarColors.muted),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: RadarColors.grid,
          child: Text(
            '$number',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
