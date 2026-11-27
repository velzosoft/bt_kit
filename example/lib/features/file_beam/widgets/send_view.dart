import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../bluetooth/tracked_device.dart';
import '../transfer/beam_payload.dart';
import '../transfer/beam_sender.dart';
import '../transfer/transfer_units.dart';
import 'beam_labels.dart';
import 'copy_record_button.dart';
import 'problem_card.dart';
import 'receiver_picker.dart';
import 'throughput_gauge.dart';

/// This phone as a sender: pick a receiver, then watch the transfer.
/// Leaving the view cancels the transfer and disconnects.
class SendView extends StatefulWidget {
  const SendView({super.key});

  @override
  State<SendView> createState() => _SendViewState();
}

class _SendViewState extends State<SendView> {
  final _sender = BeamSender();
  var _kind = BeamPayloadKind.snapshot;

  @override
  void dispose() {
    _sender.dispose();
    super.dispose();
  }

  void _send(TrackedDevice receiver) {
    final scanner = AppScope.of(context).scanner;
    final kind = _kind;
    unawaited(
      _sender.send(receiver.peripheral, () => BeamPayload.of(kind, scanner)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _sender,
    builder: (context, _) => switch (_sender.phase) {
      SendPhase.idle => ReceiverPicker(
        kind: _kind,
        onKind: (kind) => setState(() => _kind = kind),
        onSend: _send,
      ),
      SendPhase.connecting => _Progress(
        onCancel: _sender.cancel,
        children: [BeamBusy('${_sender.step}…')],
      ),
      SendPhase.sending || SendPhase.confirming => _Progress(
        onCancel: _sender.cancel,
        children: [
          BeamTitle('Sending ${_sender.payload!.name}'),
          ThroughputGauge(monitor: _sender.monitor!),
          if (_sender.phase == SendPhase.confirming)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Waiting for the receiver to check the file…',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      SendPhase.delivered => _Delivered(_sender, onDone: _sender.reset),
      SendPhase.failed => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProblemCard(
            _sender.problem!,
            onRetry: _sender.reset,
            retryLabel: 'Back to receivers',
          ),
        ],
      ),
    },
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.children, required this.onCancel});

  final List<Widget> children;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      ...children,
      const SizedBox(height: 24),
      Center(
        child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
      ),
    ],
  );
}

class _Delivered extends StatelessWidget {
  const _Delivered(this.sender, {required this.onDone});

  final BeamSender sender;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final monitor = sender.monitor!;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        BeamTitle('Delivered ${sender.payload!.name}'),
        ThroughputGauge(monitor: monitor),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified, color: RadarColors.sweep),
            const SizedBox(width: 8),
            Text(
              '${TransferUnits.bytes(monitor.total)} sent · checksum OK',
              style: text.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            FilledButton(onPressed: onDone, child: const Text('Send another')),
            CopyRecordButton(
              verb: 'sent',
              bytes: monitor.total,
              elapsed: monitor.elapsed,
              bytesPerSecond: monitor.averageBytesPerSecond,
            ),
          ],
        ),
      ],
    );
  }
}
