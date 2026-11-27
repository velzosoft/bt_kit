import 'package:material_ui/material_ui.dart';

import '../../../bluetooth/device_kind.dart';
import '../../../bluetooth/tracked_device.dart';
import '../../../widgets/kind_style.dart';
import '../../hunt/hunt_screen.dart';
import '../stay_detector.dart';

/// A device that stayed with you, by kind only: names and makers are
/// left out, since detection is not reliable enough to name anything.
class StayedDeviceTile extends StatelessWidget {
  const StayedDeviceTile({
    super.key,
    required this.stayed,
    required this.kind,
    required this.heardNow,
  });

  final StayedDevice stayed;
  final DeviceKind kind;

  /// The device while it is still heard; it can then be hunted down.
  final TrackedDevice? heardNow;

  @override
  Widget build(BuildContext context) {
    final firstSeen = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(stayed.firstSeen));
    final device = heardNow;
    final proximity = device == null
        ? 'not heard right now'
        : '${device.proximity.label.toLowerCase()} now';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        leading: KindAvatar(kind),
        title: Text(kind == DeviceKind.unknown ? 'Unknown device' : kind.label),
        subtitle: Text(
          'Stayed with you through ${stayed.stays} changes\n'
          'First seen $firstSeen · $proximity',
        ),
        isThreeLine: true,
        trailing: device == null
            ? null
            : TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HuntScreen(device: device),
                  ),
                ),
                child: const Text('Find it'),
              ),
      ),
    );
  }
}
