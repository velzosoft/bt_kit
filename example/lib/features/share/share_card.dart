import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/device_kind.dart';
import '../../bluetooth/scanner.dart';
import '../../widgets/kind_style.dart';
import '../../widgets/radar_painter.dart';

/// What the share card shows: counts and blip positions, never device ids.
final class ShareCardData {
  const ShareCardData({
    required this.count,
    required this.breakdown,
    required this.blips,
    this.caption = '',
  });

  factory ShareCardData.of(Scanner scanner) {
    final now = DateTime.now();
    return ShareCardData(
      count: scanner.count,
      breakdown: scanner.breakdown.take(4).toList(),
      blips: [
        for (final (i, device) in scanner.devices.indexed)
          _anonymous(Blip.of(device, now), i),
      ],
    );
  }

  static Blip _anonymous(Blip blip, int index) => Blip(
    id: '$index',
    kind: blip.kind,
    radius: blip.radius,
    angle: blip.angle,
  );

  final int count;
  final List<MapEntry<DeviceKind, int>> breakdown;
  final List<Blip> blips;
  final String caption;

  String get headline =>
      '$count Bluetooth ${count == 1 ? 'device' : 'devices'} around me';

  ShareCardData withCaption(String caption) => ShareCardData(
    count: count,
    breakdown: breakdown,
    blips: blips,
    caption: caption.trim(),
  );
}

/// Draws the card in a 1080 × 1350 design space, scaled to the canvas.
class ShareCardPainter extends CustomPainter {
  const ShareCardPainter(this.data);

  static const size = Size(1080, 1350);

  final ShareCardData data;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas
      ..save()
      ..scale(canvasSize.width / size.width);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = RadarColors.background,
    );

    _text(canvas, '${data.count}', 72, 64, fontSize: 200, bold: true);
    final subtitle = data.count == 1
        ? 'Bluetooth device around me'
        : 'Bluetooth devices around me';
    _text(canvas, subtitle, 72, 316, fontSize: 52);
    if (data.caption.isNotEmpty) {
      _text(
        canvas,
        data.caption,
        72,
        392,
        fontSize: 40,
        color: RadarColors.muted,
      );
    }

    RadarDrawing.paint(
      canvas,
      const Rect.fromLTWH(190, 470, 700, 700),
      blips: data.blips,
      sweep: -math.pi / 3,
      scale: 2.2,
    );

    _breakdown(canvas, 1196);
    _text(
      canvas,
      'Made with bt_kit · Flutter',
      0,
      1270,
      fontSize: 32,
      color: RadarColors.muted,
      centered: true,
    );
    canvas.restore();
  }

  void _breakdown(Canvas canvas, double top) {
    final spans = <InlineSpan>[];
    for (final MapEntry(key: kind, value: n) in data.breakdown) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '     '));
      spans
        ..add(
          TextSpan(
            text: '● ',
            style: TextStyle(color: kind.color),
          ),
        )
        ..add(TextSpan(text: kind.count(n)));
    }
    final painter = TextPainter(
      text: TextSpan(
        style: const TextStyle(color: RadarColors.text, fontSize: 34),
        children: spans,
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width - 96);
    painter.paint(canvas, Offset((size.width - painter.width) / 2, top));
  }

  void _text(
    Canvas canvas,
    String text,
    double left,
    double top, {
    required double fontSize,
    Color color = RadarColors.text,
    bool bold = false,
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: bold ? RadarColors.sweep : color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width - 2 * 72);
    final x = centered ? (size.width - painter.width) / 2 : left;
    painter.paint(canvas, Offset(x, top));
  }

  @override
  bool shouldRepaint(ShareCardPainter old) => old.data != data;
}

/// Renders the card to a PNG.
Future<Uint8List> renderShareCard(ShareCardData data) async {
  final recorder = ui.PictureRecorder();
  ShareCardPainter(data).paint(Canvas(recorder), ShareCardPainter.size);
  final image = await recorder.endRecording().toImage(
    ShareCardPainter.size.width.toInt(),
    ShareCardPainter.size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
