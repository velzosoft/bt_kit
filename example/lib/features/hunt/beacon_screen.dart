import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../app/system_settings.dart';
import '../../app/theme.dart';
import '../../bluetooth/device_kind.dart';
import '../../widgets/code_sheet.dart';
import '../../widgets/kind_style.dart';
import 'beacon_controller.dart';
import 'beacon_mode_code.dart';
import 'beacon_ripple.dart';
import 'message_panel.dart';

/// Turns this phone into something to hunt for.
class BeaconScreen extends StatefulWidget {
  const BeaconScreen({super.key});

  @override
  State<BeaconScreen> createState() => _BeaconScreenState();
}

class _BeaconScreenState extends State<BeaconScreen> {
  final _beacon = BeaconController();

  @override
  void initState() {
    super.initState();
    _beacon.start();
  }

  @override
  void dispose() {
    _beacon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Beacon mode'),
      actions: const [CodeButton(beaconModeCode)],
    ),
    body: ListenableBuilder(
      listenable: _beacon,
      builder: (context, _) => switch (_beacon.status) {
        BeaconStatus.starting => const MessagePanel.busy(
          'Starting the beacon…',
        ),
        BeaconStatus.advertising => _BeaconOn(code: _beacon.code),
        BeaconStatus.needsPermission => MessagePanel(
          icon: Icons.lock_outline,
          title: 'Bluetooth permission needed',
          body: _beacon.message ?? '',
          primary: ('Open settings', SystemSettings.openAppSettings),
          secondary: ('Try again', _beacon.start),
        ),
        BeaconStatus.unsupported => MessagePanel(
          icon: Icons.bluetooth_disabled,
          title: 'This phone cannot be a beacon',
          body: _beacon.message ?? '',
        ),
        BeaconStatus.failed => MessagePanel(
          icon: Icons.error_outline,
          title: 'The beacon did not start',
          body: _beacon.message ?? '',
          primary: ('Try again', _beacon.start),
        ),
      },
    ),
  );
}

class _BeaconOn extends StatelessWidget {
  const _BeaconOn({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: RadarColors.muted);
    const kind = DeviceKind.beacon;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          children: [
            BeaconRipple(
              color: kind.color,
              child: Icon(kind.icon, size: 64, color: kind.color),
            ),
            Text('This phone is a beacon', style: text.titleLarge),
            const SizedBox(height: 20),
            Text('Its code', style: muted),
            Text(
              code,
              style: RadarTheme.monospace.copyWith(
                fontSize: 64,
                fontWeight: FontWeight.w700,
                letterSpacing: 12,
                color: RadarColors.text,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Hide it, then on another phone open the Radar, tap the '
              'yellow beacon blip and choose Hunt. The Hunt screen shows '
              'this code, so you know it is the right beacon.',
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.stay_current_portrait),
                title: const Text('Keep this screen open'),
                subtitle: Text(
                  Platform.isIOS
                      ? 'iOS advertises only while the app is in front, so '
                            'leave the phone unlocked on this screen.'
                      : 'The beacon stops when you leave this screen.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
