import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'characteristic_controller.dart';
import 'descriptor_row.dart';
import 'gatt_names.dart';
import 'notification_log.dart';
import 'property_chips.dart';
import 'value_decoder.dart';
import 'value_view.dart';
import 'write_dialog.dart';

/// One characteristic: its properties, the Read, Write and Subscribe
/// actions, its last value, live values and descriptors.
class CharacteristicTile extends StatelessWidget {
  const CharacteristicTile({
    super.key,
    required this.controller,
    required this.connected,
    required this.writeLimit,
  });

  final CharacteristicController controller;
  final bool connected;
  final WriteLimit writeLimit;

  String get _name => GattNames.characteristic(controller.characteristic.uuid);

  Future<void> _write(BuildContext context) async {
    final request = await showWriteDialog(
      context,
      name: _name,
      properties: controller.properties,
      limit: writeLimit,
    );
    if (request == null) return;
    await controller.write(request.bytes, withResponse: request.withResponse);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final uuid = controller.characteristic.uuid;
      final value = controller.value;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name, style: text.titleSmall),
            Text(
              GattNames.uuid(uuid),
              style: RadarTheme.monospace.copyWith(
                fontSize: 12,
                color: RadarColors.muted,
              ),
            ),
            const SizedBox(height: 8),
            PropertyChips(controller.properties),
            const SizedBox(height: 4),
            _Actions(
              controller: controller,
              enabled: connected,
              onWrite: () => unawaited(_write(context)),
            ),
            if (controller.busy) const LinearProgressIndicator(minHeight: 2),
            if (controller.status case final status?)
              Text(
                status,
                style: text.bodySmall?.copyWith(
                  color: controller.failed
                      ? RadarColors.warm
                      : RadarColors.muted,
                ),
              ),
            if (value != null)
              ValueView(
                value: value,
                meaning: ValueDecoder.characteristic(uuid, value.bytes),
              ),
            if (controller.isSubscribed || controller.log.length > 0) ...[
              const SizedBox(height: 8),
              NotificationLog(controller),
            ],
            if (controller.descriptors.isNotEmpty) const SizedBox(height: 8),
            for (final descriptor in controller.descriptors)
              DescriptorRow(controller: descriptor, connected: connected),
          ],
        ),
      );
    },
  );
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.controller,
    required this.enabled,
    required this.onWrite,
  });

  final CharacteristicController controller;
  final bool enabled;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final ready = enabled && !controller.busy;
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (controller.properties.read)
          TextButton.icon(
            onPressed: ready ? () => unawaited(controller.read()) : null,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Read'),
          ),
        if (controller.canWrite)
          TextButton.icon(
            onPressed: ready ? onWrite : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Write'),
          ),
        if (controller.canSubscribe)
          FilterChip(
            label: const Text('Subscribe'),
            selected: controller.isSubscribed,
            onSelected: enabled ? controller.setSubscribed : null,
          ),
      ],
    );
  }
}
