import 'package:material_ui/material_ui.dart';

import 'player.dart';
import 'player_tile.dart';

/// Players ranked by heart rate; tiles slide when the ranking changes.
class LeaderboardView extends StatelessWidget {
  const LeaderboardView({
    super.key,
    required this.ranked,
    required this.onSelect,
    this.padding = EdgeInsets.zero,
  });

  static const _tileHeight = 108.0;
  static const _gap = 8.0;

  final List<Player> ranked;
  final ValueChanged<Player> onSelect;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.textScalerOf(context).scale(_tileHeight);
    final step = height + _gap;
    return SingleChildScrollView(
      padding: padding,
      child: SizedBox(
        height: ranked.isEmpty ? 0 : ranked.length * step - _gap,
        child: Stack(
          children: [
            for (final (index, player) in ranked.indexed)
              AnimatedPositioned(
                key: ValueKey(player.id),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOutCubic,
                top: index * step,
                left: 0,
                right: 0,
                height: height,
                child: PlayerTile(
                  player: player,
                  rank: index + 1,
                  onTap: () => onSelect(player),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
