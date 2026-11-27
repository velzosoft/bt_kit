import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'panic.dart';
import 'player.dart';

/// A player's heart rate against their own first minute, or the
/// calibration countdown until that minute is over.
class PanicMeter extends StatelessWidget {
  const PanicMeter({
    super.key,
    required this.player,
    this.barHeight = 6,
    this.style,
  });

  static const _neutral = Color(0x99ffffff);

  final Player player;
  final double barHeight;

  /// The label's style; muted body text by default.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (fill, color, label) = _reading();
    final labelStyle =
        style ??
        Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: RadarColors.muted);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(height: barHeight / 2 + 2),
        PanicBar(fill: fill, color: color, height: barHeight),
      ],
    );
  }

  (double, Color, String) _reading() {
    final baseline = player.baseline;
    if (baseline.isCalibrating) {
      final remaining = baseline.remainingAt(DateTime.now());
      final window = HeartRateBaseline.window.inMilliseconds;
      final done = 1 - remaining.inMilliseconds / window;
      return (done, _neutral, 'Calibrating · ${remaining.inSeconds} s');
    }
    final panic = player.panic;
    if (panic == null) {
      return (0, _neutral, 'Baseline ${baseline.value!.round()}');
    }
    final sign = panic.percent >= 0 ? '+' : '−';
    return (
      panic.meter,
      panicColor(panic.meter),
      '${panic.level.label} $sign${panic.percent.abs()}%',
    );
  }
}

/// Blue when calm, orange in a panic. No greens, for the chroma key.
Color panicColor(double meter) =>
    Color.lerp(RadarColors.cold, RadarColors.warm, meter)!;

class PanicBar extends StatelessWidget {
  const PanicBar({
    super.key,
    required this.fill,
    required this.color,
    this.height = 6,
  });

  final double fill;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height / 2),
    child: SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x33ffffff)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fill.clamp(0.0, 1.0),
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}
