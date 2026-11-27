import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../model/lab_test_id.dart';
import '../model/test_progress.dart';
import '../model/test_result.dart';
import 'lab_controller.dart';
import 'outcome_style.dart';

/// One test: whether it runs, its criterion, live progress and result.
class TestTile extends StatelessWidget {
  const TestTile({super.key, required this.id, required this.controller});

  final LabTestId id;
  final LabController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final result = controller.results[id];
    final running = controller.running == id;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: controller.selected.contains(id),
                  onChanged: controller.isRunning
                      ? null
                      : (on) => controller.toggle(id, on: on ?? false),
                ),
                Expanded(child: Text(id.title, style: text.titleSmall)),
                if (result != null) OutcomeBadge(result.outcome),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    id.criterion(controller.plan),
                    style: text.bodySmall?.copyWith(color: RadarColors.muted),
                  ),
                  if (running) _Progress(controller.progress[id]),
                  if (result != null) _Result(result),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.progress);

  final TestProgress? progress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: progress?.fraction),
        const SizedBox(height: 6),
        Text(
          progress?.summary ?? 'Starting…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _Result extends StatelessWidget {
  const _Result(this.result);

  final TestResult result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.summary, style: text.bodyMedium),
          for (final check in result.checks) _CheckRow(check),
          for (final note in result.notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: text.bodySmall?.copyWith(color: RadarColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.check);

  final Check check;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = check.passed ? RadarColors.sweep : RadarColors.warm;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            check.passed ? Icons.check : Icons.close,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: check.name, style: text.bodySmall),
                  TextSpan(
                    text: '  ${check.detail}',
                    style: text.bodySmall?.copyWith(color: RadarColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
