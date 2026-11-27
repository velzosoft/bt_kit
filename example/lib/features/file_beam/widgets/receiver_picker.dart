import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/bluetooth_state_panel.dart';
import '../../../app/theme.dart';
import '../../../bluetooth/app_uuids.dart';
import '../../../bluetooth/scanner.dart';
import '../../../bluetooth/tracked_device.dart';
import '../../../widgets/kind_style.dart';
import '../transfer/beam_payload.dart';

/// Picks what to send and which nearby receiver gets it. Receivers come
/// from the app's shared scan, filtered to those advertising File beam.
class ReceiverPicker extends StatelessWidget {
  const ReceiverPicker({
    super.key,
    required this.kind,
    required this.onKind,
    required this.onSend,
  });

  final BeamPayloadKind kind;
  final ValueChanged<BeamPayloadKind> onKind;
  final ValueChanged<TrackedDevice> onSend;

  static List<TrackedDevice> receiversIn(Scanner scanner) {
    final now = DateTime.now();
    return [
      for (final device in scanner.bySignal)
        if (device.data.serviceUuids.contains(AppUuids.fileBeam) &&
            device.silenceAt(now) < TrackedDevice.fadeAfter)
          device,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scanner = AppScope.of(context).scanner;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        if (BluetoothStatePanel.needed(scanner.status)) {
          return BluetoothStatePanel(scanner: scanner);
        }
        final receivers = receiversIn(scanner);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('What to send', style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<BeamPayloadKind>(
              segments: const [
                ButtonSegment(
                  value: BeamPayloadKind.snapshot,
                  icon: Icon(Icons.radar),
                  label: Text('Radar snapshot'),
                ),
                ButtonSegment(
                  value: BeamPayloadKind.test,
                  icon: Icon(Icons.speed),
                  label: Text('1 MB test'),
                ),
              ],
              selected: {kind},
              onSelectionChanged: (selection) => onKind(selection.single),
            ),
            const SizedBox(height: 24),
            Text('Nearby receivers', style: text.titleSmall),
            const SizedBox(height: 8),
            if (receivers.isEmpty)
              const _NoReceivers()
            else
              for (final device in receivers)
                _ReceiverTile(device, onTap: () => onSend(device)),
          ],
        );
      },
    );
  }
}

class _ReceiverTile extends StatelessWidget {
  const _ReceiverTile(this.device, {required this.onTap});

  final TrackedDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: KindAvatar(device.kind),
      title: Text(device.name ?? 'Nearby phone'),
      subtitle: Text('${device.proximity.label} · ready to receive'),
      trailing: const Icon(Icons.send, color: RadarColors.sweep),
      onTap: onTap,
    ),
  );
}

class _NoReceivers extends StatelessWidget {
  const _NoReceivers();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 16),
            Text('No receivers found yet', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              'On the other phone, open More › File beam and tap Receive. '
              'Keep the phones close; it shows up here within seconds.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: RadarColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
