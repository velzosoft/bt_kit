import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/heart_rate.dart';
import 'heart_beat.dart';
import 'panic_meter.dart';
import 'player.dart';

/// One row of the leaderboard. Greyed out while the strap reconnects.
class PlayerTile extends StatelessWidget {
  const PlayerTile({
    super.key,
    required this.player,
    required this.rank,
    required this.onTap,
  });

  final Player player;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedOpacity(
      opacity: player.isLive ? 1 : 0.45,
      duration: const Duration(milliseconds: 300),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(color: player.color, child: const SizedBox(width: 6)),
              SizedBox(
                width: 44,
                child: Center(
                  child: Text(
                    '$rank',
                    style: text.titleLarge?.copyWith(color: RadarColors.muted),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    _StatusLine(player),
                    const SizedBox(height: 8),
                    PanicMeter(player: player),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _BpmReadout(player),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.player);

  final Player player;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final (text, warning) = _status();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(
        color: warning ? RadarColors.warm : RadarColors.muted,
      ),
    );
  }

  /// The text, and whether it asks the player to do something.
  (String, bool) _status() => switch (player.status) {
    PlayerStatus.live
        when player.measurement?.contact == SensorContact.notDetected =>
      ('No skin contact: adjust your strap', true),
    PlayerStatus.live => (_sensorLine(), false),
    PlayerStatus.unsupported => (player.statusText, true),
    PlayerStatus.connecting ||
    PlayerStatus.reconnecting => (player.statusText, false),
  };

  String _sensorLine() {
    final battery = player.battery;
    return battery == null
        ? player.sensorName
        : '${player.sensorName} · battery $battery%';
  }
}

class _BpmReadout extends StatelessWidget {
  const _BpmReadout(this.player);

  final Player player;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bpm = player.measurement?.bpm;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HeartBeat(bpm: player.bpm, color: player.color, size: 20),
            const SizedBox(width: 6),
            Text(
              bpm == null || bpm == 0 ? '--' : '$bpm',
              style: text.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Text('BPM', style: text.labelSmall?.copyWith(color: RadarColors.muted)),
      ],
    );
  }
}
