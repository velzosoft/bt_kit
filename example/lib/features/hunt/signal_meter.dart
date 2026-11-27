import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'hunt_signal.dart';
import 'signal_trend.dart';

/// A big ring that fills and warms up as the signal gets stronger, flashes
/// with every click, and shows the warmer/colder trend in its center.
class SignalMeter extends StatefulWidget {
  const SignalMeter({super.key, required this.reading, required this.clicks});

  final HuntReading reading;
  final ValueListenable<int> clicks;

  @override
  State<SignalMeter> createState() => _SignalMeterState();
}

class _SignalMeterState extends State<SignalMeter>
    with SingleTickerProviderStateMixin {
  late final _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    widget.clicks.addListener(_onClick);
  }

  @override
  void didUpdateWidget(SignalMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clicks == widget.clicks) return;
    oldWidget.clicks.removeListener(_onClick);
    widget.clicks.addListener(_onClick);
  }

  @override
  void dispose() {
    widget.clicks.removeListener(_onClick);
    _flash.dispose();
    super.dispose();
  }

  void _onClick() => _flash.forward(from: 0);

  @override
  Widget build(BuildContext context) {
    final reading = widget.reading;
    return AspectRatio(
      aspectRatio: 1,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: reading.strength),
        duration: const Duration(milliseconds: 300),
        builder: (context, strength, center) => AnimatedBuilder(
          animation: _flash,
          builder: (context, _) => CustomPaint(
            painter: _MeterPainter(
              strength: strength,
              color: reading.isLive
                  ? meterColor(strength)
                  : RadarColors.muted.withValues(alpha: 0.5),
              flash: reading.isLive ? 1 - _flash.value : 0,
            ),
            child: center,
          ),
        ),
        child: Center(child: _MeterCenter(reading)),
      ),
    );
  }
}

Color meterColor(double strength) =>
    Color.lerp(RadarColors.cold, RadarColors.warm, strength)!;

class _MeterCenter extends StatelessWidget {
  const _MeterCenter(this.reading);

  final HuntReading reading;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (reading) {
      HuntReading(status: HuntStatus.searching) => (
        Icons.radar,
        'Listening…',
        RadarColors.muted,
      ),
      HuntReading(status: HuntStatus.lost) => (
        Icons.signal_cellular_off,
        'Signal lost',
        RadarColors.muted,
      ),
      HuntReading(trend: Trend.warmer) => (
        Icons.trending_up,
        'Warmer',
        RadarColors.warm,
      ),
      HuntReading(trend: Trend.colder) => (
        Icons.trending_down,
        'Colder',
        RadarColors.cold,
      ),
      HuntReading(trend: Trend.steady) => (
        Icons.trending_flat,
        'Steady',
        RadarColors.text,
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required this.strength,
    required this.color,
    required this.flash,
  });

  static const _start = 0.75 * pi;
  static const _sweep = 1.5 * pi;

  final double strength;
  final Color color;
  final double flash;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.07;
    final rect = (Offset.zero & size).deflate(stroke);
    final center = rect.center;

    canvas.drawCircle(
      center,
      rect.shortestSide / 2 - stroke,
      Paint()..color = color.withValues(alpha: 0.05 + 0.12 * flash),
    );
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..color = RadarColors.grid
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    if (strength <= 0) return;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (flash > 0) {
      canvas.drawArc(
        rect,
        _start,
        _sweep * strength,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.6 * flash)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.8
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.6),
      );
    }
    canvas.drawArc(rect, _start, _sweep * strength, false, arc);
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.strength != strength || old.color != color || old.flash != flash;
}
