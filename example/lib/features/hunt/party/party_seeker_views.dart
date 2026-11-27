import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../hunt_view.dart';
import '../message_panel.dart';
import 'countdown_gate.dart';
import 'party_protocol.dart';
import 'race_clock.dart';
import 'race_time.dart';
import 'seeker_race.dart';
import 'target_picker.dart';

/// Between rounds: the target this phone will follow, and the player's
/// name.
class SeekerLobbyView extends StatelessWidget {
  const SeekerLobbyView({
    super.key,
    required this.game,
    required this.choice,
    required this.onPick,
    required this.player,
    required this.waiting,
  });

  final PartyGame game;
  final TargetChoice choice;
  final ValueChanged<String> onPick;
  final TextEditingController player;
  final String waiting;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: RadarColors.muted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Find', style: muted),
        Text('“${game.name}”', style: text.headlineMedium),
        const SizedBox(height: 16),
        TargetPicker(choice: choice, onPick: onPick),
        const SizedBox(height: 20),
        TextField(
          controller: player,
          maxLength: 16,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'Sam',
            helperText: 'The hider sees it if you win. It is never saved.',
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(waiting, style: muted)),
          ],
        ),
      ],
    );
  }
}

/// The countdown, then the hunt with a race clock.
class SeekerRaceView extends StatelessWidget {
  const SeekerRaceView({
    super.key,
    required this.race,
    required this.game,
    required this.choice,
    required this.onPick,
  });

  final SeekerRace race;
  final PartyGame game;
  final TargetChoice choice;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => switch (race.stage) {
    RaceStage.countdown || RaceStage.hunting => CountdownGate(
      startedAt: race.goAt,
      child: _Hunting(race: race, game: game, choice: choice, onPick: onPick),
    ),
    RaceStage.sending => const MessagePanel.busy('Sending your time…'),
    RaceStage.sent => MessagePanel(
      icon: Icons.check_circle_outline,
      title: 'Found it in ${formatRaceTime(race.time ?? Duration.zero)}',
      body: 'Your time went to the hider. Waiting for the others…',
    ),
    RaceStage.over => const MessagePanel(
      icon: Icons.flag_outlined,
      title: 'You left this round',
      body: 'You will join the next one.',
    ),
  };
}

class _Hunting extends StatelessWidget {
  const _Hunting({
    required this.race,
    required this.game,
    required this.choice,
    required this.onPick,
  });

  final SeekerRace race;
  final PartyGame game;
  final TargetChoice choice;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hunt = race.hunt;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TargetPicker(choice: choice, onPick: onPick),
            Expanded(
              child: hunt == null
                  ? MessagePanel(
                      icon: Icons.search,
                      title: 'Looking for “${game.name}”',
                      body:
                          'Nothing nearby matches yet. Walk around, or pick '
                          'the device yourself.',
                    )
                  : HuntView(controller: hunt),
            ),
            Center(child: RaceClock(since: race.startsAt)),
            if (race.error case final error?)
              Text(
                error,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: RadarColors.warm),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: race.canClaim ? race.claim : null,
              icon: const Icon(Icons.check_circle),
              label: const Text('Found it!'),
            ),
            const SizedBox(height: 4),
            Text(
              race.canClaim
                  ? 'Stay close for a moment, or tap Found it!'
                  : 'Found it! unlocks when the signal is strong.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: RadarColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who found it first, and this seeker's own time.
class SeekerResultView extends StatelessWidget {
  const SeekerResultView({
    super.key,
    required this.game,
    required this.race,
    required this.player,
  });

  final PartyGame game;
  final SeekerRace? race;
  final String player;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final winner = game.winner;
    final myTime = race?.stage == RaceStage.sent ? race?.time : null;
    final won =
        winner != null &&
        myTime != null &&
        winner.player == player &&
        winner.time.inMilliseconds == myTime.inMilliseconds;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Icon(
              Icons.emoji_events,
              size: 72,
              color: won ? RadarColors.warm : RadarColors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              switch (winner) {
                null => 'Round over',
                _ when won => 'You found it first!',
                _ => '${winner.player} found it first',
              },
              style: text.headlineMedium,
              textAlign: TextAlign.center,
            ),
            if (winner != null)
              Text(
                formatRaceTime(winner.time),
                style: text.displaySmall,
                textAlign: TextAlign.center,
              ),
            if (myTime != null && !won)
              Text(
                'Your time: ${formatRaceTime(myTime)}',
                style: text.titleMedium,
                textAlign: TextAlign.center,
              ),
            const Spacer(),
            Text(
              'Waiting for the next round…',
              style: text.bodyMedium?.copyWith(color: RadarColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
