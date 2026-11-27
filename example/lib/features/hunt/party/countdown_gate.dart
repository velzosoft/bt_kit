import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import 'race_time.dart';

/// Shows 3, 2, 1, Go! over [child], counted from [startedAt].
class CountdownGate extends StatefulWidget {
  const CountdownGate({
    super.key,
    required this.startedAt,
    required this.child,
  });

  final DateTime startedAt;
  final Widget child;

  @override
  State<CountdownGate> createState() => _CountdownGateState();
}

class _CountdownGateState extends State<CountdownGate> {
  static const _tick = Duration(milliseconds: 50);

  Timer? _ticker;
  String? _label;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CountdownGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String? get _current =>
      Countdown.labelAt(DateTime.now().difference(widget.startedAt));

  void _start() {
    _ticker?.cancel();
    _label = _current;
    if (_label != null) _ticker = Timer.periodic(_tick, (_) => _update());
  }

  void _update() {
    final label = _current;
    if (label == _label) return;
    if (label == null) _ticker?.cancel();
    if (label != null) {
      unawaited(
        label == 'Go!'
            ? HapticFeedback.heavyImpact()
            : HapticFeedback.mediumImpact(),
      );
    }
    setState(() => _label = label);
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (label != null)
          ColoredBox(
            color: RadarColors.background.withValues(alpha: 0.94),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 140,
                  fontWeight: FontWeight.w800,
                  color: label == 'Go!' ? RadarColors.warm : RadarColors.sweep,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
