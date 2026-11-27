import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import 'race_time.dart';

/// The time since [since], ticking in tenths of a second.
class RaceClock extends StatefulWidget {
  const RaceClock({super.key, required this.since});

  final DateTime since;

  @override
  State<RaceClock> createState() => _RaceClockState();
}

class _RaceClockState extends State<RaceClock> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    formatRaceTime(DateTime.now().difference(widget.since)),
    style: Theme.of(context).textTheme.displaySmall?.copyWith(
      color: RadarColors.text,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}
