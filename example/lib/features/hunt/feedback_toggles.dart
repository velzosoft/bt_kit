import 'package:material_ui/material_ui.dart';

import 'clicker.dart';

/// Mute and vibration switches for the app bar.
class FeedbackToggles extends StatelessWidget {
  const FeedbackToggles(this.clicker, {super.key});

  final Clicker clicker;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _Toggle(
        clicker.soundOn,
        on: (Icons.volume_up, 'Mute clicks'),
        off: (Icons.volume_off, 'Play clicks'),
      ),
      _Toggle(
        clicker.vibrationOn,
        on: (Icons.vibration, 'Stop vibrating'),
        off: (Icons.mobile_off, 'Vibrate'),
      ),
    ],
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.value, {required this.on, required this.off});

  final ValueNotifier<bool> value;
  final (IconData, String) on;
  final (IconData, String) off;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: value,
    builder: (context, enabled, _) {
      final (icon, tooltip) = enabled ? on : off;
      return IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: () => value.value = !enabled,
      );
    },
  );
}
