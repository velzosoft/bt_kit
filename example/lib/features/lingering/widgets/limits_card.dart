import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../lingering_watch.dart';
import '../stay_detector.dart';

/// How the experiment works, what it cannot see, and what it keeps.
class LimitsCard extends StatelessWidget {
  const LimitsCard({super.key});

  static final _share = '${(StayDetector.churnShare * 100).round()}%';
  static final _interval = '${LingeringWatch.interval.inSeconds} seconds';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How it works, and its limits', style: text.titleSmall),
            const SizedBox(height: 12),
            _Point(
              Icons.location_off_outlined,
              'Bluetooth cannot tell where you are, and this app never asks '
              'for your location. Instead it looks at the devices around you '
              'every $_interval. When $_share of them have been replaced, '
              'your surroundings changed.',
            ),
            const _Point(
              Icons.repeat,
              'A device that stays through ${StayDetector.staysToFlag} '
              'changes within an hour is listed here.',
            ),
            const _Point(
              Icons.shuffle,
              'Many trackers change their Bluetooth address from time to '
              'time. Each new address looks like a new device, which breaks '
              'the trail, so some trackers are never listed.',
            ),
            _Point(
              Icons.phone_iphone,
              'iOS hides some Apple advertisements from apps, so this works '
              'best on Android.'
              '${Platform.isIOS ? ' On this iPhone, expect to see less.' : ''}',
            ),
            const _Point(
              Icons.delete_outline,
              'It runs only while this screen is open. Nothing is saved: '
              'leaving the screen forgets everything.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: RadarColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    ),
  );
}
