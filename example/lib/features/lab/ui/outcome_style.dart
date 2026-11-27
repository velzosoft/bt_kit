import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../model/test_result.dart';

extension OutcomeStyle on TestOutcome {
  String get label => switch (this) {
    TestOutcome.passed => 'Passed',
    TestOutcome.failed => 'Failed',
    TestOutcome.cancelled => 'Cancelled',
    TestOutcome.error => 'Could not run',
  };

  IconData get icon => switch (this) {
    TestOutcome.passed => Icons.check_circle,
    TestOutcome.failed => Icons.cancel,
    TestOutcome.cancelled => Icons.block,
    TestOutcome.error => Icons.error_outline,
  };

  Color get color => switch (this) {
    TestOutcome.passed => RadarColors.sweep,
    TestOutcome.failed || TestOutcome.error => RadarColors.warm,
    TestOutcome.cancelled => RadarColors.muted,
  };
}

class OutcomeBadge extends StatelessWidget {
  const OutcomeBadge(this.outcome, {super.key});

  final TestOutcome outcome;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(outcome.icon, size: 16, color: outcome.color),
      const SizedBox(width: 4),
      Text(
        outcome.label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: outcome.color),
      ),
    ],
  );
}
