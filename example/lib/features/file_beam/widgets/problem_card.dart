import 'package:material_ui/material_ui.dart';

import '../../../app/system_settings.dart';
import '../../../app/theme.dart';
import '../transfer/beam_problem.dart';

/// Why a transfer stopped, with the way out: the system settings when
/// [BeamProblem.needsSettings], otherwise [onRetry].
class ProblemCard extends StatelessWidget {
  const ProblemCard(this.problem, {super.key, this.onRetry, this.retryLabel});

  final BeamProblem problem;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: RadarColors.warm),
                const SizedBox(width: 12),
                Expanded(child: Text(problem.title, style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(problem.message, style: text.bodyMedium),
            if (problem.needsSettings || onRetry != null) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: problem.needsSettings
                    ? const FilledButton(
                        onPressed: SystemSettings.openAppSettings,
                        child: Text('Open settings'),
                      )
                    : FilledButton(
                        onPressed: onRetry,
                        child: Text(retryLabel ?? 'Try again'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
