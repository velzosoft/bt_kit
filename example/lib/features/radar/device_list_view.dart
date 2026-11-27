import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/tracked_device.dart';
import '../../widgets/kind_style.dart';
import 'advertisement_details.dart';

/// The radar's devices as a list, strongest signal first.
class DeviceListView extends StatelessWidget {
  const DeviceListView({
    super.key,
    required this.devices,
    required this.onSelect,
  });

  final List<TrackedDevice> devices;
  final ValueChanged<TrackedDevice> onSelect;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.only(bottom: 24),
    itemCount: devices.length,
    separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
    itemBuilder: (context, i) =>
        _DeviceTile(devices[i], onTap: () => onSelect(devices[i])),
  );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(this.device, {required this.onTap});

  final TrackedDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KindAvatar(device.kind),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.displayName, style: text.titleSmall),
                  Text(
                    device.category.reason,
                    style: text.bodySmall?.copyWith(color: device.kind.color),
                  ),
                  const SizedBox(height: 6),
                  AdvertisementTable(device.data, maxBytes: 8),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${device.rssi.round()} dBm', style: text.titleSmall),
                Text(
                  device.proximity.label,
                  style: text.bodySmall?.copyWith(color: RadarColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
