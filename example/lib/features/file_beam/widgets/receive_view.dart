import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../transfer/beam_receiver.dart';
import '../transfer/beam_reception.dart';
import 'beam_labels.dart';
import 'problem_card.dart';
import 'received_file_card.dart';
import 'throughput_gauge.dart';

/// This phone as a receiver, from setup to the received file. Leaving the
/// view stops advertising and closes every server and channel.
class ReceiveView extends StatefulWidget {
  const ReceiveView({super.key});

  @override
  State<ReceiveView> createState() => _ReceiveViewState();
}

class _ReceiveViewState extends State<ReceiveView> {
  final _receiver = BeamReceiver();

  @override
  void initState() {
    super.initState();
    unawaited(_receiver.start());
  }

  @override
  void dispose() {
    _receiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _receiver,
    builder: (context, _) => switch (_receiver.setup) {
      ReceiverSetup.starting => const BeamBusy('Getting ready to receive…'),
      ReceiverSetup.failed => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProblemCard(_receiver.setupProblem!, onRetry: _receiver.start),
        ],
      ),
      ReceiverSetup.ready => _ready(_receiver.reception),
    },
  );

  Widget _ready(BeamReception? reception) {
    final waiting = _Waiting(advertisesName: _receiver.advertisesName);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: switch (reception?.stage) {
        null => [waiting],
        ReceptionStage.connected => [
          const BeamBusy('A phone connected. Waiting for the file…'),
        ],
        ReceptionStage.receiving => [
          BeamTitle('Receiving ${reception!.header!.name}'),
          ThroughputGauge(monitor: reception.monitor!, color: RadarColors.cold),
        ],
        ReceptionStage.received => [
          ReceivedFileCard(reception!.file!),
          const SizedBox(height: 24),
          waiting,
        ],
        ReceptionStage.failed => [
          ProblemCard(reception!.problem!),
          const SizedBox(height: 24),
          waiting,
        ],
      },
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.advertisesName});

  final bool advertisesName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shownAs = advertisesName
        ? 'This phone shows up there as "${BeamReceiver.localName}".'
        : 'This phone shows up there as a nearby phone.';
    return Column(
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.wifi_tethering, size: 72, color: RadarColors.cold),
        const SizedBox(height: 16),
        Text('Waiting for a sender', style: text.titleLarge),
        const SizedBox(height: 8),
        Text(
          'On the other phone, open More › File beam and tap Send. $shownAs',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text(
          'The link is not encrypted, so File beam only sends pictures the '
          'app makes and test data.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: RadarColors.muted),
        ),
      ],
    );
  }
}
