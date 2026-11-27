import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';

/// A number with its label, such as "50/s · Sending".
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              child: Text(
                value,
                style: text.titleLarge?.copyWith(color: RadarColors.sweep),
              ),
            ),
            Text(
              label,
              style: text.bodySmall?.copyWith(color: RadarColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
