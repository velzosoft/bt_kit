import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../model/lab_test_id.dart';
import 'lab_controller.dart';
import 'report_actions.dart';
import 'run_options.dart';
import 'target_card.dart';
import 'test_tile.dart';

/// Runs the Lab tests against a reference peripheral.
class RunTab extends StatelessWidget {
  const RunTab({super.key, required this.controller});

  final LabController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.scanner]),
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        TargetCard(controller: controller),
        const SizedBox(height: 16),
        RunOptions(controller: controller),
        for (final id in LabTestId.values)
          TestTile(id: id, controller: controller),
        const SizedBox(height: 12),
        _RunButton(controller),
        if (controller.report case final report?) ...[
          const SizedBox(height: 20),
          ReportActions(report: report),
        ],
        const SizedBox(height: 16),
        Text(
          'Keep this screen on while tests run: phones pause Bluetooth for '
          'apps in the background.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: RadarColors.muted),
        ),
      ],
    ),
  );
}

class _RunButton extends StatelessWidget {
  const _RunButton(this.controller);

  final LabController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isRunning) {
      final stopping = controller.isCancelling;
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: stopping || controller.isSkipping
                  ? null
                  : controller.skip,
              icon: const Icon(Icons.skip_next),
              label: const Text('Skip this test'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: stopping ? null : controller.cancel,
              icon: const Icon(Icons.stop),
              label: Text(stopping ? 'Stopping…' : 'Stop'),
            ),
          ),
        ],
      );
    }
    final count = controller.selected.length;
    return FilledButton.icon(
      onPressed: controller.canRun ? () => unawaited(controller.run()) : null,
      icon: const Icon(Icons.play_arrow),
      label: Text(
        '${count == 1 ? 'Run 1 test' : 'Run $count tests'} '
        '(${controller.mode.label.toLowerCase()})',
      ),
    );
  }
}
