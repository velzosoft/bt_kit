import 'package:material_ui/material_ui.dart';

import 'board_protocol.dart';

/// The board's LED on the screen, drawn from what the board reports.
///
/// Each report restarts the pattern, so it blinks with the real LED.
class VirtualLed extends StatefulWidget {
  const VirtualLed({super.key, required this.state, this.size = 22});

  /// The latest report; a new object restarts the pattern.
  final LedState? state;
  final double size;

  @override
  State<VirtualLed> createState() => _VirtualLedState();
}

class _VirtualLedState extends State<VirtualLed>
    with SingleTickerProviderStateMixin {
  late final _ticker = createTicker(_tick);
  late final _color = ValueNotifier<Color?>(
    widget.state?.colorAt(Duration.zero),
  );

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(VirtualLed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state, widget.state)) _restart();
  }

  void _restart() {
    _ticker.stop();
    final state = widget.state;
    _color.value = state?.colorAt(Duration.zero);
    if (state != null && state.isAnimated) _ticker.start();
  }

  void _tick(Duration elapsed) => _color.value = widget.state?.colorAt(elapsed);

  @override
  void dispose() {
    _ticker.dispose();
    _color.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Board LED',
    value: widget.state?.state.name ?? 'unknown',
    child: ValueListenableBuilder(
      valueListenable: _color,
      builder: (context, color, _) => _Dot(color: color, size: widget.size),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  static const _dark = Color(0xff1a2422);

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final lit = color;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.35),
            colors: lit == null
                ? const [Color(0xff2a3633), _dark]
                : [Color.lerp(lit, Colors.white, 0.55)!, lit],
          ),
          border: Border.all(
            color: lit?.withValues(alpha: 0.6) ?? const Color(0xff33423e),
          ),
          boxShadow: lit == null
              ? null
              : [
                  BoxShadow(
                    color: lit.withValues(alpha: 0.7),
                    blurRadius: size * 0.45,
                    spreadRadius: size * 0.1,
                  ),
                ],
        ),
      ),
    );
  }
}
