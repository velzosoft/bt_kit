import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// A heart that beats at [bpm], and rests when there is none.
class HeartBeat extends StatefulWidget {
  const HeartBeat({
    super.key,
    required this.bpm,
    required this.color,
    this.size = 24,
  });

  final int? bpm;
  final Color color;
  final double size;

  @override
  State<HeartBeat> createState() => _HeartBeatState();
}

class _HeartBeatState extends State<HeartBeat>
    with SingleTickerProviderStateMixin {
  static const _thump = 0.15;
  static const _growth = 0.2;

  late final _ticker = createTicker(_tick);
  final _scale = ValueNotifier<double>(1);
  var _lastTick = Duration.zero;
  var _phase = 0.0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(HeartBeat oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.bpm == null && _ticker.isActive) {
      _ticker.stop();
      _scale.value = 1;
    } else if (widget.bpm != null && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  /// Advances by beats rather than restarting an animation, so the rhythm
  /// stays smooth while the heart rate changes.
  void _tick(Duration elapsed) {
    final seconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _phase = (_phase + seconds * (widget.bpm ?? 0) / 60) % 1;
    _scale.value = _phase < _thump
        ? 1 + _growth * sin(_phase / _thump * pi)
        : 1;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _scale,
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
    child: Icon(Icons.favorite, color: widget.color, size: widget.size),
  );
}
