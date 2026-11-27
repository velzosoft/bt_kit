import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../widgets/experiment_badge.dart';

/// Says up front that this is an experiment and not a security tool.
class ExperimentNotice extends StatelessWidget {
  const ExperimentNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: RadarColors.warm.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExperimentBadge(),
            const SizedBox(height: 10),
            Text(
              'This is an experiment, not a security tool. It can miss '
              'devices, and it can list harmless ones, such as your own '
              'watch or the phone of someone travelling with you.',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
