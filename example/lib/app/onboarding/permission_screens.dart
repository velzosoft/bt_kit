import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../system_settings.dart';
import '../theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) => _MessageScreen(
    icon: Icons.radar,
    title: 'Bluetooth Radar',
    body:
        'Bluetooth Radar listens for the Bluetooth devices around you and '
        'shows them on a radar; nothing leaves your phone.',
    primary: ('Allow Bluetooth', onAllow),
  );
}

class PermissionDeniedScreen extends StatelessWidget {
  const PermissionDeniedScreen({super.key, this.onAskAgain});

  final VoidCallback? onAskAgain;

  @override
  Widget build(BuildContext context) => _MessageScreen(
    icon: Icons.bluetooth_disabled,
    title: 'No Bluetooth permission yet',
    body: Platform.isIOS
        ? 'To see devices around you, turn on Bluetooth for BT Radar in '
              'Settings. Come back here when you are done.'
        : 'To see devices around you, allow "Nearby devices" for BT Radar '
              'in Settings. Come back here when you are done.',
    primary: ('Open settings', SystemSettings.openAppSettings),
    secondary: onAskAgain == null ? null : ('Ask again', onAskAgain!),
  );
}

class NotDeclaredScreen extends StatelessWidget {
  const NotDeclaredScreen({super.key});

  @override
  Widget build(BuildContext context) => const _MessageScreen(
    icon: Icons.build_outlined,
    title: 'Bluetooth is not configured',
    body:
        'This build does not declare its Bluetooth permissions in '
        'AndroidManifest.xml or Info.plist. See the bt_kit README.',
  );
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.icon,
    required this.title,
    required this.body,
    this.primary,
    this.secondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final (String, VoidCallback)? primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(icon, size: 96, color: RadarColors.sweep),
              const SizedBox(height: 32),
              Text(
                title,
                style: text.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                body,
                style: text.bodyLarge?.copyWith(color: RadarColors.muted),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              if (primary case (final label, final onPressed))
                FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(label),
                ),
              if (secondary case (final label, final onPressed)) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: onPressed, child: Text(label)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
