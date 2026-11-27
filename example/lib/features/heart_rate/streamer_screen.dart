import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/heart_rate.dart';
import 'heart_beat.dart';
import 'panic_meter.dart';
import 'player.dart';
import 'showdown.dart';

/// Full-screen heart rates on chroma-key green, for screen capture into a
/// live stream. Cards are opaque so the key removes only the background.
class StreamerScreen extends StatefulWidget {
  const StreamerScreen({super.key, required this.showdown});

  final Showdown showdown;

  @override
  State<StreamerScreen> createState() => _StreamerScreenState();
}

class _StreamerScreenState extends State<StreamerScreen> {
  static const _controlsFor = Duration(seconds: 3);

  var _controlsVisible = true;
  Timer? _hideControls;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideControls?.cancel();
    _hideControls = Timer(_controlsFor, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: RadarColors.chromaKey,
    body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showControls,
      child: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MediaQuery.withNoTextScaling(
                  child: ListenableBuilder(
                    listenable: widget.showdown,
                    builder: (context, _) =>
                        _StreamerGrid(widget.showdown.leaderboard),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: IconButton.filled(
                      tooltip: 'Exit streamer mode',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StreamerGrid extends StatelessWidget {
  const _StreamerGrid(this.ranked);

  final List<Player> ranked;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (ranked.isEmpty) return const SizedBox.shrink();
      final landscape = constraints.maxWidth > constraints.maxHeight;
      final columns = _columns(ranked.length, landscape: landscape);
      final rows = (ranked.length / columns).ceil();
      return Column(
        children: [
          for (var row = 0; row < rows; row++)
            Expanded(
              child: Row(
                children: [
                  for (var column = 0; column < columns; column++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: _cardAt(row * columns + column),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _cardAt(int index) => index < ranked.length
      ? _StreamerCard(ranked[index], rank: index + 1)
      : const SizedBox.shrink();

  static int _columns(int count, {required bool landscape}) => landscape
      ? (count <= 3 ? count : (count / 2).ceil())
      : (count <= 3 ? 1 : 2);
}

class _StreamerCard extends StatelessWidget {
  const _StreamerCard(this.player, {required this.rank});

  static const _card = Color(0xff101414);
  static const _greyed = Color(0xff6f7674);

  final Player player;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final live = player.isLive;
    final accent = live ? player.color : _greyed;
    final bpm = player.measurement?.bpm;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent, width: 6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FittedBox(
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '#$rank',
                      style: const TextStyle(fontSize: 28, color: _greyed),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        player.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HeartBeat(bpm: player.bpm, color: accent, size: 64),
                    const SizedBox(width: 12),
                    Text(
                      bpm == null || bpm == 0 ? '--' : '$bpm',
                      style: TextStyle(
                        fontSize: 128,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: live ? Colors.white : _greyed,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                PanicMeter(
                  player: player,
                  barHeight: 14,
                  style: const TextStyle(fontSize: 24, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  _hint() ?? ' ',
                  style: const TextStyle(fontSize: 22, color: RadarColors.warm),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _hint() => switch (player.status) {
    PlayerStatus.connecting => 'Connecting…',
    PlayerStatus.reconnecting => 'Reconnecting…',
    PlayerStatus.unsupported => 'Not a heart-rate sensor',
    PlayerStatus.live
        when player.measurement?.contact == SensorContact.notDetected =>
      'Adjust your strap',
    PlayerStatus.live => null,
  };
}
