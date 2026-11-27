import 'package:material_ui/material_ui.dart';

/// Rings that keep spreading out from [child], like a signal going out.
class BeaconRipple extends StatefulWidget {
  const BeaconRipple({
    super.key,
    required this.color,
    required this.child,
    this.size = 200,
  });

  final Color color;
  final double size;
  final Widget child;

  @override
  State<BeaconRipple> createState() => _BeaconRippleState();
}

class _BeaconRippleState extends State<BeaconRipple>
    with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: CustomPaint(
      painter: _RipplePainter(_wave, widget.color),
      child: Center(child: widget.child),
    ),
  );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.wave, this.color) : super(repaint: wave);

  static const _rings = 3;

  final Animation<double> wave;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    for (var ring = 0; ring < _rings; ring++) {
      final progress = (wave.value + ring / _rings) % 1;
      canvas.drawCircle(
        center,
        maxRadius * (0.3 + 0.7 * progress),
        Paint()
          ..color = color.withValues(alpha: 0.5 * (1 - progress))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.color != color;
}
