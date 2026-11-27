import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/hex.dart';
import 'attribute_controller.dart';
import 'gatt_names.dart';
import 'value_decoder.dart';

/// One descriptor of a characteristic, with its value once read.
class DescriptorRow extends StatelessWidget {
  const DescriptorRow({
    super.key,
    required this.controller,
    required this.connected,
  });

  final DescriptorController controller;
  final bool connected;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final uuid = controller.descriptor.uuid;
      final muted = text.bodySmall?.copyWith(color: RadarColors.muted);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              Icons.subdirectory_arrow_right,
              size: 16,
              color: RadarColors.muted,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(GattNames.descriptor(uuid), style: text.bodySmall),
                Text(
                  GattNames.uuid(uuid),
                  style: RadarTheme.monospace.copyWith(
                    fontSize: 11,
                    color: RadarColors.muted,
                  ),
                ),
                if (controller.value case final value?)
                  SelectableText(
                    [
                      if (value.bytes.isEmpty) 'Empty' else value.bytes.toHex(),
                      ?ValueDecoder.descriptor(uuid, value.bytes),
                    ].join('  ·  '),
                    style: RadarTheme.monospace.copyWith(fontSize: 12),
                  ),
                if (controller.status case final status?)
                  Text(
                    status,
                    style: controller.failed
                        ? muted?.copyWith(color: RadarColors.warm)
                        : muted,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Read descriptor',
            visualDensity: VisualDensity.compact,
            icon: controller.busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined, size: 20),
            onPressed: connected && !controller.busy
                ? () => unawaited(controller.read())
                : null,
          ),
        ],
      );
    },
  );
}
