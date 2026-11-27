import 'package:material_ui/material_ui.dart';

import '../../bluetooth/scanner.dart';
import '../../bluetooth/tracked_device.dart';
import '../../widgets/radar_painter.dart';

/// The animated radar. Tapping near a blip selects its device.
class RadarView extends StatefulWidget {
  const RadarView({
    super.key,
    required this.scanner,
    required this.onSelect,
    this.selectedId,
  });

  final Scanner scanner;
  final ValueChanged<TrackedDevice> onSelect;
  final String? selectedId;

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  static const _tapRadius = 28.0;

  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  List<Blip> _blips() {
    final now = DateTime.now();
    return [for (final device in widget.scanner.devices) Blip.of(device, now)];
  }

  void _onTap(Offset position, Size size) {
    final geometry = RadarGeometry(Offset.zero & size);
    final now = DateTime.now();
    TrackedDevice? nearest;
    var nearestDistance = _tapRadius;
    for (final device in widget.scanner.devices) {
      final distance =
          (geometry.position(Blip.of(device, now)) - position).distance;
      if (distance < nearestDistance) {
        nearest = device;
        nearestDistance = distance;
      }
    }
    if (nearest != null) widget.onSelect(nearest);
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _onTap(details.localPosition, size),
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: RadarPainter(
                blips: _blips,
                sweep: _sweep,
                selectedId: widget.selectedId,
              ),
            ),
          ),
        );
      },
    ),
  );
}
