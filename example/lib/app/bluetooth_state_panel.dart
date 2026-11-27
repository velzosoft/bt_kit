import 'dart:io';

import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../bluetooth/scanner.dart';
import 'system_settings.dart';
import 'theme.dart';

/// Explains why the scan is not running and offers the way out.
class BluetoothStatePanel extends StatelessWidget {
  const BluetoothStatePanel({super.key, required this.scanner});

  final Scanner scanner;

  static bool needed(ScanStatus status) =>
      status != ScanStatus.scanning && status != ScanStatus.idle;

  @override
  Widget build(BuildContext context) => switch (scanner.status) {
    ScanStatus.bluetoothOff => _Panel(
      icon: Icons.bluetooth_disabled,
      title: 'Bluetooth is off',
      body: Platform.isIOS
          ? 'Turn it on in Control Center or in Settings › Bluetooth. '
                'The radar starts by itself.'
          : 'Turn it on and the radar starts by itself.',
      action: BtKit.instance.capabilities.requestEnable
          ? ('Turn on Bluetooth', _requestEnable)
          : null,
    ),
    ScanStatus.unauthorized => const _Panel(
      icon: Icons.lock_outline,
      title: 'Bluetooth permission is off',
      body: 'Allow Bluetooth for this app in the system settings.',
      action: ('Open settings', SystemSettings.openAppSettings),
    ),
    ScanStatus.unsupported => const _Panel(
      icon: Icons.bluetooth_disabled,
      title: 'No Bluetooth Low Energy',
      body: 'This device has no Bluetooth Low Energy radio.',
    ),
    ScanStatus.failed => _Panel(
      icon: Icons.error_outline,
      title: 'The scan stopped',
      body: scanner.error ?? 'Something went wrong.',
      action: ('Try again', scanner.retry),
    ),
    ScanStatus.scanning || ScanStatus.idle => const SizedBox.shrink(),
  };

  static Future<void> _requestEnable() async {
    try {
      await BtKit.instance.requestEnable();
    } on BluetoothException catch (_) {}
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: RadarColors.muted),
            const SizedBox(height: 16),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              style: text.bodyMedium?.copyWith(color: RadarColors.muted),
              textAlign: TextAlign.center,
            ),
            if (action case (final label, final onPressed)) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onPressed, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}
