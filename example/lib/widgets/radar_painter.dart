import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../bluetooth/device_kind.dart';
import '../bluetooth/signal.dart';
import '../bluetooth/tracked_device.dart';
import 'kind_style.dart';

/// One device as the radar draws it.
final class Blip {
  const Blip({
    required this.id,
    required this.kind,
    required this.radius,
    required this.angle,
    this.opacity = 1,
  });

  Blip.of(TrackedDevice device, DateTime now)
    : id = device.id,
      kind = device.kind,
      radius = Signal.radius(device.rssi),
      angle = Signal.angle(device.id),
      opacity = device.opacityAt(now);

  final String id;
  final DeviceKind kind;

  /// From 0 (center) to 1 (edge).
  final double radius;
  final double angle;
  final double opacity;
}

/// Where things are on a radar of a given size.
final class RadarGeometry {
  RadarGeometry(Rect area)
    : center = area.center,
      radius = area.shortestSide / 2 - 4;

  final Offset center;
  final double radius;

  Offset position(Blip blip) =>
      center +
      Offset(math.cos(blip.angle), math.sin(blip.angle)) *
          (blip.radius * radius);
}

/// Draws the radar: rings, the rotating sweep and the blips.
abstract final class RadarDrawing {
  static const sweepWidth = math.pi / 2.5;
  static const blipSize = 9.0;

  static final _rings = [
    (Signal.radius(Signal.nearAbove), Proximity.near),
    (Signal.radius(Signal.farBelow), Proximity.around),
    (1.0, Proximity.far),
  ];

  static void paint(
    Canvas canvas,
    Rect area, {
    required List<Blip> blips,
    required double sweep,
    String? selectedId,
    double scale = 1,
  }) {
    final geometry = RadarGeometry(area);
    _background(canvas, geometry, scale);
    _sweep(canvas, geometry, sweep);
    for (final blip in blips) {
      _blip(canvas, geometry, blip, sweep, scale, blip.id == selectedId);
    }
  }

  static void _background(Canvas canvas, RadarGeometry g, double scale) {
    canvas.drawCircle(
      g.center,
      g.radius,
      Paint()
        ..shader = ui.Gradient.radial(g.center, g.radius, [
          const Color(0xff0d2a22),
          RadarColors.background,
        ]),
    );
    final line = Paint()
      ..color = RadarColors.grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = scale;
    canvas
      ..drawLine(
        g.center - Offset(g.radius, 0),
        g.center + Offset(g.radius, 0),
        line,
      )
      ..drawLine(
        g.center - Offset(0, g.radius),
        g.center + Offset(0, g.radius),
        line,
      );
    for (final (fraction, proximity) in _rings) {
      canvas.drawCircle(g.center, g.radius * fraction, line);
      final label = TextPainter(
        text: TextSpan(
          text: proximity.label.toUpperCase(),
          style: TextStyle(
            color: RadarColors.muted.withValues(alpha: 0.7),
            fontSize: 9 * scale,
            letterSpacing: 1.5 * scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        g.center + Offset(4 * scale, -g.radius * fraction + 3 * scale),
      );
    }
  }

  static void _sweep(Canvas canvas, RadarGeometry g, double sweep) {
    final rect = Rect.fromCircle(center: g.center, radius: g.radius);
    canvas
      ..drawCircle(
        g.center,
        g.radius,
        Paint()
          ..shader = SweepGradient(
            colors: [
              RadarColors.sweep.withValues(alpha: 0),
              RadarColors.sweep.withValues(alpha: 0),
              RadarColors.sweep.withValues(alpha: 0.28),
            ],
            stops: const [0, 1 - sweepWidth / (2 * math.pi), 1],
            transform: GradientRotation(sweep),
          ).createShader(rect),
      )
      ..drawLine(
        g.center,
        g.center + Offset(math.cos(sweep), math.sin(sweep)) * g.radius,
        Paint()
          ..color = RadarColors.sweep.withValues(alpha: 0.8)
          ..strokeWidth = 1.5,
      );
  }

  static void _blip(
    Canvas canvas,
    RadarGeometry g,
    Blip blip,
    double sweep,
    double scale,
    bool selected,
  ) {
    final position = g.position(blip);
    final size = blipSize * scale;
    final color = blip.kind.color;
    final sinceSweep = (sweep - blip.angle) % (2 * math.pi) / (2 * math.pi);
    final echo = math.pow(1 - sinceSweep, 6).toDouble();
    if (echo > 0.02) {
      canvas.drawCircle(
        position,
        size * (1.4 + echo),
        Paint()..color = color.withValues(alpha: 0.35 * echo * blip.opacity),
      );
    }
    canvas.drawCircle(
      position,
      size,
      Paint()..color = color.withValues(alpha: 0.85 * blip.opacity),
    );
    _KindSprites.draw(canvas, blip.kind, position, size * 1.25, blip.opacity);
    if (selected) {
      canvas.drawCircle(
        position,
        size * 1.9,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale,
      );
    }
  }
}

/// Kind icons rendered once to images, so hundreds of blips draw cheaply.
abstract final class _KindSprites {
  static const _pixels = 64;
  static final _images = <DeviceKind, ui.Image>{};

  static void draw(
    Canvas canvas,
    DeviceKind kind,
    Offset center,
    double size,
    double opacity,
  ) {
    final image = _images[kind] ??= _render(kind);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, _pixels.toDouble(), _pixels.toDouble()),
      Rect.fromCenter(center: center, width: size, height: size),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..filterQuality = FilterQuality.medium,
    );
  }

  static ui.Image _render(DeviceKind kind) {
    final recorder = ui.PictureRecorder();
    final icon = kind.icon;
    TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: _pixels.toDouble(),
            color: const Color(0xff04100c),
          ),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout()
      ..paint(Canvas(recorder), Offset.zero);
    return recorder.endRecording().toImageSync(_pixels, _pixels);
  }
}

/// The live radar: repaints every frame from [blips].
class RadarPainter extends CustomPainter {
  RadarPainter({required this.blips, required this.sweep, this.selectedId})
    : super(repaint: sweep);

  final List<Blip> Function() blips;
  final Animation<double> sweep;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) => RadarDrawing.paint(
    canvas,
    Offset.zero & size,
    blips: blips(),
    sweep: sweep.value * 2 * math.pi,
    selectedId: selectedId,
  );

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.selectedId != selectedId || old.sweep != sweep;
}
