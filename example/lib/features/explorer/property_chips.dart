import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

/// A characteristic's properties as small labels.
class PropertyChips extends StatelessWidget {
  const PropertyChips(this.properties, {super.key});

  final CharacteristicProperties properties;

  static List<String> labels(CharacteristicProperties properties) => [
    if (properties.read) 'Read',
    if (properties.write) 'Write',
    if (properties.writeWithoutResponse) 'Write without response',
    if (properties.notify) 'Notify',
    if (properties.indicate) 'Indicate',
    if (properties.broadcast) 'Broadcast',
    if (properties.authenticatedSignedWrites) 'Signed write',
    if (properties.extendedProperties) 'Extended properties',
  ];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: RadarColors.muted);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in labels(properties))
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: RadarColors.grid),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(label, style: style),
            ),
          ),
      ],
    );
  }
}
