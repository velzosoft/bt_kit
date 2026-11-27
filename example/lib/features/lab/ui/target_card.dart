import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../bluetooth/scanner.dart';
import 'lab_controller.dart';

/// The reference peripherals the shared scan hears, and which one the
/// tests run against.
class TargetCard extends StatelessWidget {
  const TargetCard({super.key, required this.controller});

  final LabController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: RadarColors.muted);
    final references = controller.references;
    final target = controller.target;
    final scanning = controller.scanner.status == ScanStatus.scanning;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reference peripheral', style: text.titleSmall),
            const SizedBox(height: 4),
            if (!scanning)
              Text(
                'The scan is not running, so none can be found.',
                style: muted,
              )
            else if (references.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Looking for one… On a second phone, open the Lab and '
                  'choose Be the reference, or flash firmware that '
                  'implements example/peripheral/README.md.',
                  style: muted,
                ),
              ),
            for (final device in references)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  device.id == target?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: RadarColors.sweep,
                ),
                title: Text(device.displayName),
                subtitle: Text(
                  '${device.rssi.round()} dBm · ${device.proximity.label}',
                ),
                onTap: controller.isRunning
                    ? null
                    : () => controller.choose(device),
              ),
          ],
        ),
      ),
    );
  }
}
