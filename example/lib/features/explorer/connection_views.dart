import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'failure_text.dart';
import 'explorer_controller.dart';

/// Connecting and discovering, with a way out.
class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key, required this.explorer, required this.name});

  final ExplorerController explorer;
  final String name;

  @override
  Widget build(BuildContext context) {
    final discovering = explorer.phase == ExplorerPhase.discovering;
    return _Message(
      leading: const SizedBox.square(
        dimension: 40,
        child: CircularProgressIndicator(),
      ),
      title: discovering ? 'Listing services' : 'Connecting to $name',
      body: discovering
          ? 'Finding services, characteristics and descriptors.'
          : 'Keep the device close and awake.',
      action: OutlinedButton(
        onPressed: explorer.cancel,
        child: const Text('Cancel'),
      ),
    );
  }
}

/// Why the connection or discovery failed, and a way to try again.
class FailedView extends StatelessWidget {
  const FailedView(this.explorer, {super.key});

  final ExplorerController explorer;

  @override
  Widget build(BuildContext context) {
    final failure = explorer.failure;
    final cancelled = failure is OperationCancelledException;
    final title = cancelled
        ? 'Not connected'
        : explorer.failedDuring == ExplorerPhase.discovering
        ? 'Could not list services'
        : 'Could not connect';
    return _Message(
      leading: Icon(
        cancelled ? Icons.link_off : Icons.error_outline,
        size: 40,
        color: cancelled ? RadarColors.muted : RadarColors.warm,
      ),
      title: title,
      body: cancelled || failure == null
          ? 'Connect when you are ready.'
          : '${explainFailure(failure)}.\n\n'
                'Some devices accept one connection at a time, or only '
                'from their own app.',
      action: FilledButton.icon(
        onPressed: () => unawaited(explorer.connect()),
        icon: const Icon(Icons.refresh),
        label: Text(cancelled ? 'Connect' : 'Try again'),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.leading,
    required this.title,
    required this.body,
    required this.action,
  });

  final Widget leading;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(height: 24),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              style: text.bodyMedium?.copyWith(color: RadarColors.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            action,
          ],
        ),
      ),
    );
  }
}
