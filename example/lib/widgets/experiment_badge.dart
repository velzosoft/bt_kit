import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';

class ExperimentBadge extends StatelessWidget {
  const ExperimentBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: RadarColors.warm),
    ),
    child: Text(
      'EXPERIMENT',
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: RadarColors.warm),
    ),
  );
}
