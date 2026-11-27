import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'characteristic_tile.dart';
import 'explorer_controller.dart';
import 'gatt_names.dart';

/// A service and its characteristics.
class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.service, required this.explorer});

  final GattService service;
  final ExplorerController explorer;

  @override
  Widget build(BuildContext context) {
    final count = service.characteristics.length;
    final details = [
      GattNames.uuid(service.uuid),
      count == 1 ? '1 characteristic' : '$count characteristics',
      if (!service.isPrimary) 'secondary',
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(service),
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(GattNames.service(service.uuid)),
        subtitle: Text(
          details.join(' · '),
          style: RadarTheme.monospace.copyWith(
            fontSize: 12,
            color: RadarColors.muted,
          ),
        ),
        children: [
          for (final (index, characteristic)
              in service.characteristics.indexed) ...[
            if (index > 0) const Divider(height: 1),
            CharacteristicTile(
              controller: explorer.controllerFor(characteristic),
              connected: explorer.isConnected,
              writeLimit: explorer.maximumWriteLength,
            ),
          ],
        ],
      ),
    );
  }
}
