import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../bluetooth/tracked_device.dart';
import '../../widgets/kind_style.dart';
import '../explorer/explorer_screen.dart';
import '../hunt/hunt_screen.dart';
import 'advertisement_details.dart';

Future<void> showDeviceSheet(BuildContext context, TrackedDevice device) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DeviceSheet(device),
    );

/// A device's card: what it is, how strong its signal is, its parsed
/// advertisement, and the Hunt and Connect actions.
class DeviceSheet extends StatelessWidget {
  const DeviceSheet(this.device, {super.key});

  final TrackedDevice device;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context)
      ..pop()
      ..push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final connectable = device.data.isConnectable ?? true;
    return ListenableBuilder(
      listenable: AppScope.of(context).scanner,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                KindAvatar(device.kind, size: 52),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.displayName, style: text.titleLarge),
                      Text(
                        '${device.kind.label} · ${device.category.reason}',
                        style: text.bodyMedium?.copyWith(
                          color: device.kind.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SignalRow(device),
            const SizedBox(height: 20),
            Text('Advertisement', style: text.titleSmall),
            const SizedBox(height: 6),
            AdvertisementTable(device.data, maxBytes: 24),
            const SizedBox(height: 8),
            Text(
              'Id ${device.id}',
              style: text.bodySmall?.copyWith(color: RadarColors.muted),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _open(context, HuntScreen(device: device)),
                    icon: const Icon(Icons.track_changes),
                    label: const Text('Hunt'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: connectable
                        ? () => _open(context, ExplorerScreen(device: device))
                        : null,
                    icon: const Icon(Icons.link),
                    label: Text(connectable ? 'Connect' : 'Not connectable'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow(this.device);

  final TrackedDevice device;

  @override
  Widget build(BuildContext context) {
    final silence = device.silenceAt(DateTime.now()).inSeconds;
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Chip(
          label: Text(device.proximity.label),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 12),
        Text('${device.rssi.round()} dBm', style: style),
        const Spacer(),
        Text(
          silence < 2 ? 'Heard just now' : 'Heard ${silence}s ago',
          style: style?.copyWith(color: RadarColors.muted),
        ),
      ],
    );
  }
}
