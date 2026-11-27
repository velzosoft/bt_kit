import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/bluetooth_state_panel.dart';
import '../../app/theme.dart';
import '../../bluetooth/app_uuids.dart';
import '../../bluetooth/tracked_device.dart';
import '../../widgets/code_sheet.dart';
import 'message_panel.dart';
import 'party/party_code.dart';
import 'party/party_seeker_screen.dart';

/// Parties hosted nearby, found in the app's shared scan.
class PartyJoinScreen extends StatelessWidget {
  const PartyJoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scanner = AppScope.of(context).scanner;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a party'),
        actions: const [CodeButton(partyCode)],
      ),
      body: ListenableBuilder(
        listenable: scanner,
        builder: (context, _) {
          if (BluetoothStatePanel.needed(scanner.status)) {
            return BluetoothStatePanel(scanner: scanner);
          }
          final parties = [
            for (final device in scanner.bySignal)
              if (device.data.serviceUuids.contains(AppUuids.party)) device,
          ];
          return parties.isEmpty
              ? const MessagePanel(
                  icon: Icons.celebration_outlined,
                  title: 'Looking for parties…',
                  body:
                      'Ask the hider to open one: Radar, tap a device, Hunt, '
                      'then Start a party. It shows up here when their phone '
                      'is nearby.',
                )
              : _PartyList(parties);
        },
      ),
    );
  }
}

class _PartyList extends StatelessWidget {
  const _PartyList(this.parties);

  final List<TrackedDevice> parties;

  void _join(BuildContext context, TrackedDevice party) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PartySeekerScreen(host: party.peripheral),
        ),
      );

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        'The closest party is first.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: RadarColors.muted),
      ),
      const SizedBox(height: 8),
      for (final party in parties)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.celebration, color: RadarColors.sweep),
            title: const Text('Party nearby'),
            subtitle: Text(party.proximity.label),
            trailing: FilledButton(
              onPressed: () => _join(context, party),
              child: const Text('Join'),
            ),
            onTap: () => _join(context, party),
          ),
        ),
    ],
  );
}
