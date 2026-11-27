import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/device_kind.dart';
import '../../widgets/kind_style.dart';

/// "143 Bluetooth devices around you", with a breakdown by kind.
class RadarHeader extends StatelessWidget {
  const RadarHeader({super.key, required this.count, required this.breakdown});

  final int count;
  final List<MapEntry<DeviceKind, int>> breakdown;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$count',
                  style: text.displaySmall?.copyWith(
                    color: RadarColors.sweep,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: count == 1
                      ? ' Bluetooth device around you'
                      : ' Bluetooth devices around you',
                  style: text.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final MapEntry(key: kind, value: n) in breakdown)
                KindCount(kind: kind, count: n),
            ],
          ),
        ],
      ),
    );
  }
}

class KindCount extends StatelessWidget {
  const KindCount({super.key, required this.kind, required this.count});

  final DeviceKind kind;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(kind.icon, size: 14, color: kind.color),
      const SizedBox(width: 4),
      Text(
        kind.count(count),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: RadarColors.muted),
      ),
    ],
  );
}
