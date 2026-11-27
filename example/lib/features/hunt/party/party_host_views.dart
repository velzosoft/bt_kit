import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../bluetooth/tracked_device.dart';
import '../target_header.dart';
import 'countdown_gate.dart';
import 'fingerprint_hint.dart';
import 'party_host.dart';
import 'race_clock.dart';
import 'race_time.dart';
import 'target_fingerprint.dart';

/// Naming the hidden device before the party opens.
class HostSetupView extends StatelessWidget {
  const HostSetupView({
    super.key,
    required this.target,
    required this.fingerprint,
    required this.name,
    required this.onOpen,
  });

  final TrackedDevice target;
  final TargetFingerprint fingerprint;
  final TextEditingController name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: RadarColors.muted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Seekers will hunt for', style: muted),
        const SizedBox(height: 8),
        TargetHeader(
          kind: target.kind,
          title: target.displayName,
          detail: '${target.kind.label} · ${target.category.reason}',
        ),
        const SizedBox(height: 24),
        TextField(
          controller: name,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What did you hide?',
            hintText: 'Cookie jar',
            helperText: 'Seekers see this name.',
          ),
          onSubmitted: (_) => onOpen(),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18, color: RadarColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(fingerprintHint(fingerprint), style: muted)),
          ],
        ),
        const SizedBox(height: 24),
        ListenableBuilder(
          listenable: name,
          builder: (context, _) => FilledButton.icon(
            onPressed: name.text.trim().isEmpty ? null : onOpen,
            icon: const Icon(Icons.celebration_outlined),
            label: const Text('Open the party'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your phone hosts the party over Bluetooth. Nothing goes anywhere '
          'else, and the party ends when you leave this screen.',
          style: text.bodySmall?.copyWith(color: RadarColors.muted),
        ),
      ],
    );
  }
}

/// Waiting for seekers, then starting the hunt.
class HostLobbyView extends StatelessWidget {
  const HostLobbyView({super.key, required this.host});

  final PartyHost host;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: RadarColors.muted);
    final seekers = host.seekers;
    return _Page(
      children: [
        const Icon(Icons.celebration, size: 64, color: RadarColors.sweep),
        const SizedBox(height: 12),
        Text(
          '“${host.game.name}”',
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          host.game.round == 0
              ? 'Your party is open.'
              : 'Hide it somewhere new, then start the next round.',
          style: muted,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Text(
          switch (seekers) {
            0 => 'Waiting for seekers…',
            1 => '1 seeker is in',
            _ => '$seekers seekers are in',
          },
          style: text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'They join from More › Join a party, on their own phones.',
          style: muted,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: seekers > 0 ? host.startRound : null,
          icon: const Icon(Icons.flag),
          label: const Text('Start the hunt'),
        ),
      ],
    );
  }
}

/// The countdown, then the clock while seekers hunt.
class HostRaceView extends StatelessWidget {
  const HostRaceView({super.key, required this.host});

  final PartyHost host;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final goAt = host.goAt ?? DateTime.now();
    return CountdownGate(
      startedAt: goAt,
      child: _Page(
        children: [
          const Spacer(),
          Text(
            'Seekers are hunting for',
            style: text.bodyMedium?.copyWith(color: RadarColors.muted),
            textAlign: TextAlign.center,
          ),
          Text(
            '“${host.game.name}”',
            style: text.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Center(child: RaceClock(since: goAt.add(Countdown.length))),
          const Spacer(),
          OutlinedButton(
            onPressed: host.endRound,
            child: const Text('Stop the round'),
          ),
        ],
      ),
    );
  }
}

/// Who found it, and how fast.
class HostResultView extends StatelessWidget {
  const HostResultView({super.key, required this.host});

  final PartyHost host;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final winner = host.game.winner;
    return _Page(
      children: [
        const Spacer(),
        const Icon(Icons.emoji_events, size: 72, color: RadarColors.warm),
        const SizedBox(height: 12),
        Text(
          winner == null ? 'Round over' : '${winner.player} found it',
          style: text.headlineMedium,
          textAlign: TextAlign.center,
        ),
        if (winner != null)
          Text(
            formatRaceTime(winner.time),
            style: text.displaySmall,
            textAlign: TextAlign.center,
          ),
        const Spacer(),
        FilledButton.icon(
          onPressed: host.endRound,
          icon: const Icon(Icons.replay),
          label: const Text('Next round'),
        ),
      ],
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}
