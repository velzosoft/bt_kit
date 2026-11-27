import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../widgets/code_sheet.dart';
import 'add_player_sheet.dart';
import 'leaderboard_view.dart';
import 'no_players_view.dart';
import 'player.dart';
import 'player_sheet.dart';
import 'showdown.dart';
import 'showdown_code.dart';
import 'streamer_screen.dart';

/// Live heart rates of up to six people, ranked, with a panic meter each.
///
/// Lives in a kept-alive tab, so the straps stay connected while other tabs
/// are shown; leaving the app's home disconnects them all.
class ShowdownScreen extends StatefulWidget {
  const ShowdownScreen({super.key});

  @override
  State<ShowdownScreen> createState() => _ShowdownScreenState();
}

class _ShowdownScreenState extends State<ShowdownScreen> {
  final _showdown = Showdown();

  @override
  void dispose() {
    _showdown.dispose();
    super.dispose();
  }

  void _addPlayers() => showAddPlayerSheet(context, _showdown);

  void _openPlayer(Player player) =>
      showPlayerSheet(context, _showdown, player);

  void _openStreamerMode() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StreamerScreen(showdown: _showdown),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _showdown,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Heart-rate showdown'),
        actions: [
          IconButton(
            tooltip: 'Streamer mode',
            icon: const Icon(Icons.live_tv),
            onPressed: _showdown.isEmpty ? null : _openStreamerMode,
          ),
          const CodeButton(showdownCode),
        ],
      ),
      body: _showdown.isEmpty
          ? NoPlayersView(onAdd: _addPlayers)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LeaderboardHeader(count: _showdown.players.length),
                Expanded(
                  child: LeaderboardView(
                    ranked: _showdown.leaderboard,
                    onSelect: _openPlayer,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  ),
                ),
              ],
            ),
      floatingActionButton: _showdown.isEmpty || _showdown.isFull
          ? null
          : FloatingActionButton.extended(
              onPressed: _addPlayers,
              icon: const Icon(Icons.person_add),
              label: const Text('Add player'),
            ),
    ),
  );
}

class _LeaderboardHeader extends StatelessWidget {
  const _LeaderboardHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Text(
      '$count of ${Showdown.maxPlayers} players · panic is each heart rate '
      'against its own first minute',
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: RadarColors.muted),
    ),
  );
}
