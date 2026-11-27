import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'hue_ramp.dart';

/// Tells a [PressCircle] what the board's button does.
final class PressCircleController extends ChangeNotifier {
  _CircleEvent? _event;
  var _held = false;

  /// Whether the button is down, as far as the circle knows.
  bool get isHeld => _held;

  /// The button went down [held] ago: the circle appears and grows.
  void grow({Duration held = Duration.zero}) {
    _held = true;
    _emit(_Grow(held));
  }

  /// The button came up after [held], as the board measured it: the circle
  /// pops and the time shows.
  void pop(Duration held, {required int presses}) {
    _held = false;
    _emit(_Pop(held, presses));
  }

  /// The link dropped: the circle fades out.
  void fade() {
    _held = false;
    _emit(const _Fade());
  }

  void _emit(_CircleEvent event) {
    _event = event;
    notifyListeners();
  }
}

/// The size of the circle while the button is held.
abstract final class PressGeometry {
  static const minRadius = 12.0;
  static const growDuration = HueRamp.duration;
  static const wobble = 0.03;
  static const wobbleHz = 2.0;
  static const popGrowth = 0.1;
  static const endDuration = Duration(milliseconds: 300);
  static const resultDuration = Duration(milliseconds: 1500);

  /// The radius after a hold of [held]: from [minRadius] to [maxRadius]
  /// along an ease-out curve.
  static double radius(Duration held, {required double maxRadius}) {
    final progress = (held.inMicroseconds / growDuration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    final eased = Curves.easeOutCubic.transform(progress);
    return minRadius + (max(maxRadius, minRadius) - minRadius) * eased;
  }

  /// 1 while the circle grows, then a gentle wobble at full size.
  static double wobbleAt(Duration held) {
    final over = held - growDuration;
    if (over <= Duration.zero) return 1;
    return 1 + wobble * sin(2 * pi * wobbleHz * over.inMicroseconds / 1e6);
  }
}

/// A circle that grows while the board's button is held and pops when it
/// is released, animated from the phone's own clock.
class PressCircle extends StatefulWidget {
  const PressCircle({super.key, required this.controller, this.hint});

  static const paintKey = Key('press-circle-paint');

  final PressCircleController controller;

  /// Shown while there is no circle and no result.
  final Widget? hint;

  @override
  State<PressCircle> createState() => _PressCircleState();
}

enum _Phase { idle, growing, popping, fading }

class _PressCircleState extends State<PressCircle>
    with SingleTickerProviderStateMixin {
  late final _ticker = createTicker(_tick);
  var _now = Duration.zero;
  var _phase = _Phase.idle;
  var _holdStart = Duration.zero;
  var _releasedAfter = Duration.zero;
  var _endStart = Duration.zero;
  var _hapticSecond = 0;
  _Pop? _result;
  var _resultStart = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onEvent);
  }

  @override
  void didUpdateWidget(PressCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onEvent);
      widget.controller.addListener(_onEvent);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEvent);
    _ticker.dispose();
    super.dispose();
  }

  void _onEvent() {
    if (!_ticker.isActive) {
      _now = Duration.zero;
      _ticker.start();
    }
    switch (widget.controller._event) {
      case _Grow(:final held):
        _phase = _Phase.growing;
        _holdStart = _now - held;
        _hapticSecond = min(held.inSeconds, _lastHapticSecond);
        _result = null;
      case final _Pop pop:
        _end(_Phase.popping);
        _result = pop;
        _resultStart = _now;
      case _Fade():
        _end(_Phase.fading);
      case null:
        return;
    }
    setState(() {});
  }

  void _end(_Phase phase) {
    if (_phase != _Phase.growing) return;
    _phase = phase;
    _releasedAfter = _now - _holdStart;
    _endStart = _now;
  }

  static final _lastHapticSecond = PressGeometry.growDuration.inSeconds;

  void _tick(Duration elapsed) {
    _now = elapsed;
    if (_phase == _Phase.growing) _haptics(_now - _holdStart);
    if (_phase != _Phase.growing &&
        _now - _endStart >= PressGeometry.endDuration) {
      _phase = _Phase.idle;
    }
    if (_result != null &&
        _now - _resultStart >= PressGeometry.resultDuration) {
      _result = null;
    }
    if (_phase == _Phase.idle && _result == null) _ticker.stop();
    setState(() {});
  }

  void _haptics(Duration held) {
    final second = min(held.inSeconds, _lastHapticSecond);
    while (_hapticSecond < second) {
      _hapticSecond++;
      unawaited(
        _hapticSecond == _lastHapticSecond
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.lightImpact(),
      );
    }
  }

  _CircleFrame? _frame(double maxRadius) {
    double radiusAfter(Duration held) =>
        PressGeometry.radius(held, maxRadius: maxRadius) *
        PressGeometry.wobbleAt(held);
    switch (_phase) {
      case _Phase.idle:
        return null;
      case _Phase.growing:
        final held = _now - _holdStart;
        return _CircleFrame(radiusAfter(held), HueRamp.color(held), 1);
      case _Phase.popping || _Phase.fading:
        final t =
            ((_now - _endStart).inMicroseconds /
                    PressGeometry.endDuration.inMicroseconds)
                .clamp(0.0, 1.0);
        final growth = _phase == _Phase.popping
            ? 1 + PressGeometry.popGrowth * Curves.easeOut.transform(t)
            : 1.0;
        return _CircleFrame(
          radiusAfter(_releasedAfter) * growth,
          HueRamp.color(_releasedAfter),
          1 - t,
        );
    }
  }

  double get _resultOpacity {
    const fade = Duration(milliseconds: 250);
    final left = PressGeometry.resultDuration - (_now - _resultStart);
    return (left.inMicroseconds / fade.inMicroseconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final frame = _frame(constraints.biggest.shortestSide / 2);
      final result = _result;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              key: PressCircle.paintKey,
              painter: PressCirclePainter(
                radius: frame?.radius ?? 0,
                color: frame?.color ?? Colors.transparent,
                opacity: frame?.opacity ?? 0,
              ),
            ),
            if (frame == null && result == null && widget.hint != null)
              Center(child: widget.hint),
            if (result != null)
              Center(
                child: Opacity(
                  opacity: _resultOpacity,
                  child: _ResultLabel(result),
                ),
              ),
          ],
        ),
      );
    },
  );
}

final class _CircleFrame {
  const _CircleFrame(this.radius, this.color, this.opacity);

  final double radius;
  final Color color;
  final double opacity;
}

class PressCirclePainter extends CustomPainter {
  const PressCirclePainter({
    required this.radius,
    required this.color,
    required this.opacity,
  });

  final double radius;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0 || opacity <= 0) return;
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      radius * 1.06,
      Paint()
        ..color = color.withValues(alpha: 0.35 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, min(radius * 0.2, 32)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [
            Color.lerp(color, Colors.white, 0.35)!.withValues(alpha: opacity),
            color.withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(PressCirclePainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity;
}

class _ResultLabel extends StatelessWidget {
  const _ResultLabel(this.result);

  final _Pop result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final seconds = result.held.inMilliseconds / 1000;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${seconds.toStringAsFixed(1)} s',
          style: text.displayLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: const [Shadow(blurRadius: 16)],
          ),
        ),
        Text(
          'press ${result.presses}',
          style: text.titleMedium?.copyWith(color: RadarColors.muted),
        ),
      ],
    );
  }
}

sealed class _CircleEvent {
  const _CircleEvent();
}

final class _Grow extends _CircleEvent {
  const _Grow(this.held);

  final Duration held;
}

final class _Pop extends _CircleEvent {
  const _Pop(this.held, this.presses);

  final Duration held;
  final int presses;
}

final class _Fade extends _CircleEvent {
  const _Fade();
}
