import 'package:material_ui/material_ui.dart';

import '../features/board/board_screen.dart';
import '../features/file_beam/file_beam_screen.dart';
import '../features/hunt/beacon_screen.dart';
import '../features/hunt/party_join_screen.dart';
import '../features/lingering/lingering_screen.dart';
import '../widgets/experiment_badge.dart';
import 'theme.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More')),
    body: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: const [
        _Section('Play'),
        _Entry(
          icon: Icons.cell_tower,
          title: 'Beacon mode',
          subtitle: 'Turn this phone into something to hunt for.',
          screen: BeaconScreen(),
        ),
        _Entry(
          icon: Icons.celebration_outlined,
          title: 'Join a party',
          subtitle:
              'Race your friends to a hidden device. Start one from Hunt.',
          screen: PartyJoinScreen(),
        ),
        _Entry(
          icon: Icons.developer_board,
          title: 'Hello board',
          subtitle: 'Press the button on an ESP32 and see it here.',
          screen: BoardScreen(),
        ),
        _Section('Share'),
        _Entry(
          icon: Icons.send_to_mobile,
          title: 'File beam',
          subtitle: 'Send a picture to a nearby phone, no internet needed.',
          screen: FileBeamScreen(),
        ),
        _Section('Experiments'),
        _Entry(
          icon: Icons.travel_explore,
          title: 'Things that stayed with you',
          subtitle:
              'Devices that keep showing up while everything else changes.',
          screen: LingeringScreen(),
          experiment: true,
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: RadarColors.muted, letterSpacing: 1.2),
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
    this.experiment = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
  final bool experiment;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: RadarColors.sweep),
      title: Row(
        children: [
          Flexible(child: Text(title)),
          if (experiment) ...[
            const SizedBox(width: 8),
            const ExperimentBadge(),
          ],
        ],
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => screen)),
    ),
  );
}
