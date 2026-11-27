import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../peripheral/reference_peripheral.dart';
import 'stat_tile.dart';

/// This phone as the reference peripheral for a Lab on another phone.
class ServeTab extends StatelessWidget {
  const ServeTab({super.key, required this.peripheral});

  final ReferencePeripheral peripheral;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: peripheral,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text(
          'Serve the Lab reference profile so that another phone can run '
          'the tests against this one. Keep this screen open.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _StatusCard(peripheral),
        if (peripheral.status == ServeStatus.serving) ...[
          const SizedBox(height: 16),
          _Stats(peripheral),
          const SizedBox(height: 16),
          _Centrals(peripheral),
        ],
      ],
    ),
  );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(this.peripheral);

  final ReferencePeripheral peripheral;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = peripheral.status;
    final (icon, title, detail) = switch (status) {
      ServeStatus.stopped => (
        Icons.podcasts,
        'Not serving',
        'Advertises the Lab service and serves its GATT profile.',
      ),
      ServeStatus.starting => (Icons.podcasts, 'Starting…', ''),
      ServeStatus.serving => (
        Icons.podcasts,
        'Serving as the reference',
        'Advertising the Lab service as ${peripheral.advertisedAs}.',
      ),
      ServeStatus.failed => (
        Icons.error_outline,
        'Could not start',
        peripheral.error ?? '',
      ),
    };
    final serving = status == ServeStatus.serving;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              icon,
              color: serving ? RadarColors.sweep : RadarColors.muted,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      style: text.bodySmall?.copyWith(color: RadarColors.muted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (serving)
              OutlinedButton(
                onPressed: () => unawaited(peripheral.stop()),
                child: const Text('Stop'),
              )
            else
              FilledButton(
                onPressed: status == ServeStatus.starting
                    ? null
                    : () => unawaited(peripheral.start()),
                child: const Text('Start'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats(this.peripheral);

  final ReferencePeripheral peripheral;

  @override
  Widget build(BuildContext context) {
    final stream = peripheral.stream;
    final error = peripheral.lastSendError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.5,
          children: [
            StatTile(label: 'Centrals', value: '${peripheral.centrals.length}'),
            StatTile(label: 'Subscribed', value: '${peripheral.subscriptions}'),
            StatTile(
              label: 'Stream',
              value: stream == null
                  ? 'off'
                  : '${stream.kind.name} ${stream.rateHz} Hz',
            ),
            StatTile(label: 'Sending', value: '${peripheral.sendRateHz}/s'),
            StatTile(label: 'Sent', value: '${peripheral.sent}'),
            StatTile(
              label: 'Send failures',
              value: '${peripheral.sendFailures}',
            ),
            StatTile(label: 'Reads', value: '${peripheral.reads}'),
            StatTile(label: 'Writes', value: '${peripheral.writes}'),
            StatTile(label: 'Fault', value: peripheral.fault?.name ?? 'none'),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Last send failure: $error',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: RadarColors.warm),
            ),
          ),
      ],
    );
  }
}

class _Centrals extends StatelessWidget {
  const _Centrals(this.peripheral);

  final ReferencePeripheral peripheral;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final centrals = peripheral.centrals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Centrals', style: text.titleSmall),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            centrals.isEmpty
                ? 'None yet.'
                : 'iOS lists a central once it reads, writes or subscribes, '
                      'and keeps it after it disconnects.',
            style: text.bodySmall?.copyWith(color: RadarColors.muted),
          ),
        ),
        for (final central in centrals)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.smartphone),
            title: Text(central.id, style: RadarTheme.monospace),
            subtitle: Text(
              '${central.maximumUpdateLength} bytes per notification',
            ),
          ),
      ],
    );
  }
}
