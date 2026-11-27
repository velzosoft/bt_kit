import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'failure_text.dart';
import 'explorer_controller.dart';

/// Facts about the link (signal, MTU, write limits) and the requests that
/// change them. MTU and priority requests exist on Android only.
class LinkCard extends StatelessWidget {
  const LinkCard(this.explorer, {super.key});

  final ExplorerController explorer;

  static Future<void> _run(
    BuildContext context,
    Future<String?> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    String? message;
    try {
      message = await action();
    } on BluetoothException catch (e) {
      message = explainFailure(e);
    }
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = explorer.isConnected;
    final capabilities = BtKit.instance.capabilities;
    final rssi = explorer.rssi;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Link', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _Fact('Signal', rssi == null ? '–' : '$rssi dBm'),
                _Fact('MTU', connected ? '${explorer.mtu}' : '–'),
                _Fact(
                  'Longest write',
                  connected
                      ? '${explorer.maximumWriteLength(withResponse: true)} B, '
                            '${explorer.maximumWriteLength(withResponse: false)}'
                            ' B without response'
                      : '–',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: connected
                      ? () => _run(context, () async {
                          await explorer.readRssi();
                          return null;
                        })
                      : null,
                  icon: const Icon(Icons.network_cell),
                  label: const Text('Read RSSI'),
                ),
                if (capabilities.requestMtu)
                  OutlinedButton.icon(
                    onPressed: connected
                        ? () => _run(
                            context,
                            () async =>
                                'MTU is ${await explorer.requestLargestMtu()}',
                          )
                        : null,
                    icon: const Icon(Icons.unfold_more),
                    label: const Text(
                      'Request MTU ${ExplorerController.largestMtu}',
                    ),
                  ),
                if (capabilities.connectionPriority)
                  OutlinedButton.icon(
                    onPressed: connected
                        ? () => _run(context, () async {
                            await explorer.requestHighPriority();
                            return 'Android accepted high priority';
                          })
                        : null,
                    icon: const Icon(Icons.bolt),
                    label: const Text('High priority'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: RadarColors.muted)),
        Text(value, style: text.bodyMedium),
      ],
    );
  }
}
