import 'package:material_ui/material_ui.dart';

import '../bluetooth/device_kind.dart';

extension KindStyle on DeviceKind {
  Color get color => switch (this) {
    DeviceKind.phone => const Color(0xff35d6f0),
    DeviceKind.computer => const Color(0xff5b8cff),
    DeviceKind.audio => const Color(0xffb47cff),
    DeviceKind.wearable => const Color(0xffff6fb5),
    DeviceKind.health => const Color(0xffff5a5f),
    DeviceKind.tracker => const Color(0xffffa53d),
    DeviceKind.beacon => const Color(0xfff5e14b),
    DeviceKind.input => const Color(0xff3ee0b8),
    DeviceKind.media => const Color(0xff8f9bff),
    DeviceKind.home => const Color(0xffa6e34f),
    DeviceKind.unknown => const Color(0xff8a9a95),
  };

  IconData get icon => switch (this) {
    DeviceKind.phone => Icons.smartphone,
    DeviceKind.computer => Icons.laptop,
    DeviceKind.audio => Icons.headphones,
    DeviceKind.wearable => Icons.watch,
    DeviceKind.health => Icons.monitor_heart,
    DeviceKind.tracker => Icons.sell,
    DeviceKind.beacon => Icons.cell_tower,
    DeviceKind.input => Icons.keyboard,
    DeviceKind.media => Icons.tv,
    DeviceKind.home => Icons.lightbulb,
    DeviceKind.unknown => Icons.bluetooth,
  };
}

/// A round, colored icon for a device kind.
class KindAvatar extends StatelessWidget {
  const KindAvatar(this.kind, {super.key, this.size = 40});

  final DeviceKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: kind.color.withValues(alpha: 0.18),
      border: Border.all(color: kind.color.withValues(alpha: 0.6)),
    ),
    child: Icon(kind.icon, color: kind.color, size: size * 0.55),
  );
}
