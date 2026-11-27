import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../transfer/transfer_monitor.dart';
import '../transfer/transfer_units.dart';

/// A speedometer for a transfer: the live rate on an arc, then progress,
/// size and time below it. Once finished, it shows the average rate.
class ThroughputGauge extends StatelessWidget {
  const ThroughputGauge({
    super.key,
    required this.monitor,
    this.color = RadarColors.sweep,
  });

  final TransferMonitor monitor;
  final Color color;

  /// Full-scale values in KB/s; the arc picks the first above the peak.
  static const _scales = [64, 128, 256, 512, 1024, 2048, 4096];

  static double _fullScale(double bytesPerSecond) {
    for (final kilobytes in _scales) {
      final bytes = kilobytes * TransferUnits.kilobyte.toDouble();
      if (bytesPerSecond <= bytes) return bytes;
    }
    return _scales.last * TransferUnits.kilobyte.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final finished = monitor.isFinished;
    final rate = finished
        ? monitor.averageBytesPerSecond
        : monitor.bytesPerSecond;
    final scale = _fullScale(math.max(monitor.peakBytesPerSecond, rate));
    final percent = (monitor.progress * 100).floor();
    final time = TransferUnits.duration(monitor.elapsed);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 190,
          child: CustomPaint(
            painter: _ArcPainter(fraction: rate / scale, color: color),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    TransferUnits.kilobytesPerSecond(rate),
                    style: RadarTheme.monospace.copyWith(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: RadarColors.text,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    finished ? 'KB/s average' : 'KB/s',
                    style: text.bodyMedium?.copyWith(color: RadarColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: monitor.progress,
          minHeight: 8,
          color: color,
          backgroundColor: RadarColors.grid,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${TransferUnits.bytes(monitor.transferred)} of '
                '${TransferUnits.bytes(monitor.total)}',
                style: text.bodyMedium,
              ),
            ),
            Text('$percent%', style: text.bodyMedium),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          finished ? 'Total time $time' : 'Elapsed $time',
          style: text.bodySmall?.copyWith(color: RadarColors.muted),
        ),
      ],
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.fraction, required this.color});

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;
  static const _stroke = 14.0;

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height * 1.15) / 2 - _stroke;
    final center = Offset(size.width / 2, size.height / 2 + _stroke / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      paint..color = RadarColors.grid,
    );
    final value = fraction.clamp(0.0, 1.0);
    if (value > 0) {
      canvas.drawArc(rect, _start, _sweep * value, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.fraction != fraction || old.color != color;
}
