import 'package:material_ui/material_ui.dart';

import '../model/lab_plan.dart';
import 'lab_controller.dart';

/// Quick or full runs, and whether to test pairing.
class RunOptions extends StatelessWidget {
  const RunOptions({super.key, required this.controller});

  final LabController controller;

  @override
  Widget build(BuildContext context) {
    final locked = controller.isRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<LabMode>(
          segments: [
            for (final mode in LabMode.values)
              ButtonSegment(value: mode, label: Text(mode.label)),
          ],
          selected: {controller.mode},
          onSelectionChanged: locked
              ? null
              : (modes) => controller.setMode(modes.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include pairing'),
          subtitle: const Text(
            'Reads the encrypted characteristic; both phones ask to pair',
          ),
          value: controller.includePairing,
          onChanged: locked ? null : controller.setIncludePairing,
        ),
      ],
    );
  }
}
