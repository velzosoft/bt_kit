import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

/// A calm, centered message with up to two actions.
class MessagePanel extends StatelessWidget {
  const MessagePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.primary,
    this.secondary,
  });

  /// A spinner with a title.
  const MessagePanel.busy(String title, {Key? key})
    : this(key: key, icon: null, title: title, body: '');

  final IconData? icon;
  final String title;
  final String body;
  final (String, VoidCallback)? primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final icon?)
              Icon(icon, size: 56, color: RadarColors.muted)
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                body,
                style: text.bodyMedium?.copyWith(color: RadarColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (primary case (final label, final onPressed)) ...[
              const SizedBox(height: 24),
              FilledButton(onPressed: onPressed, child: Text(label)),
            ],
            if (secondary case (final label, final onPressed)) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onPressed, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}
