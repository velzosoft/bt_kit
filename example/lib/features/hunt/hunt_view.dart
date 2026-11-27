import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/signal.dart';
import 'hunt_controller.dart';
import 'hunt_signal.dart';
import 'signal_meter.dart';

/// The Geiger counter's face: the meter and a line about the signal.
class HuntView extends StatelessWidget {
  const HuntView({super.key, required this.controller});

  final HuntController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final reading = controller.reading;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SignalMeter(
                reading: reading,
                clicks: controller.clicker.clicks,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _describe(reading),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: RadarColors.muted),
          ),
        ],
      );
    },
  );

  static String _describe(HuntReading reading) => switch (reading) {
    HuntReading(status: HuntStatus.live, :final rssi?) =>
      '${Signal.proximity(rssi).label} · ${rssi.round()} dBm',
    HuntReading(status: HuntStatus.lost, :final silence?) =>
      'Not heard for ${silence.inSeconds} s. It may be out of range, '
          'asleep or switched off.',
    HuntReading(status: HuntStatus.lost) =>
      'Not heard yet. It may be out of range, asleep or switched off.',
    _ => 'Waiting for its next advertisement',
  };
}
