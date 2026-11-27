import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/bluetooth_state_panel.dart';
import '../../app/theme.dart';
import '../../bluetooth/scanner.dart';
import '../../bluetooth/signal.dart';
import '../../widgets/code_sheet.dart';
import 'board_code.dart';
import 'board_link.dart';
import 'board_picker.dart';
import 'board_protocol.dart';
import 'press_circle.dart';
import 'virtual_led.dart';

/// An ESP32 and this phone respond to each other: the board's button draws
/// a circle here, and Blink flashes the board's LED.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final Scanner _scanner = AppScope.of(context).scanner;
  late final BoardLink _link = BoardLink(_scanner);
  final _circle = PressCircleController();
  StreamSubscription<ButtonEvent>? _buttonEvents;
  var _color = BlinkColor.values.first;
  BoardStatus? _status;
  var _pickerOpen = false;

  @override
  void initState() {
    super.initState();
    _link.addListener(_onLink);
    _buttonEvents = _link.buttonEvents.listen(_onButton);
    _link.start();
  }

  @override
  void dispose() {
    unawaited(_buttonEvents?.cancel());
    _link
      ..removeListener(_onLink)
      ..dispose();
    _circle.dispose();
    super.dispose();
  }

  void _onButton(ButtonEvent event) => event.pressed
      ? _circle.grow(held: event.held)
      : _circle.pop(event.held, presses: event.presses);

  void _onLink() {
    final status = _link.status;
    if (status == _status) return;
    _status = status;
    if (status != BoardStatus.ready && _circle.isHeld) _circle.fade();
    if (status == BoardStatus.choosing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _choose());
    }
  }

  Future<void> _choose() async {
    if (!mounted || _pickerOpen) return;
    _pickerOpen = true;
    await showBoardPicker(context, _link);
    _pickerOpen = false;
  }

  Future<void> _blink() async {
    final problem = await _link.blink(_color.color);
    if (problem == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(problem)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Hello board'),
      actions: const [CodeButton(boardCode)],
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([_scanner, _link]),
      builder: (context, _) {
        if (BluetoothStatePanel.needed(_scanner.status)) {
          return BluetoothStatePanel(scanner: _scanner);
        }
        final others = _link.nearby.where((b) => b.id != _link.board?.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              link: _link,
              onSwitch: _link.board != null && others.isNotEmpty
                  ? _choose
                  : null,
            ),
            Expanded(
              child: PressCircle(
                controller: _circle,
                hint: _Hint(link: _link, onChoose: _choose),
              ),
            ),
            _BlinkControls(
              selected: _color,
              onSelect: (color) => setState(() => _color = color),
              onBlink: _link.isReady ? _blink : null,
            ),
          ],
        );
      },
    ),
  );
}

enum BlinkColor {
  white('White', Color(0xffffffff)),
  red('Red', Color(0xffff0000)),
  green('Green', Color(0xff00ff00)),
  blue('Blue', Color(0xff0000ff)),
  yellow('Yellow', Color(0xffffff00)),
  magenta('Magenta', Color(0xffff00ff));

  const BlinkColor(this.label, this.color);

  final String label;
  final Color color;
}

class _Header extends StatelessWidget {
  const _Header({required this.link, required this.onSwitch});

  final BoardLink link;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rssi = link.rssi;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          VirtualLed(state: link.led, size: 26),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  link.board?.displayName ?? 'No board yet',
                  style: text.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  link.status.label,
                  style: text.bodySmall?.copyWith(
                    color: link.isReady ? RadarColors.sweep : RadarColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (rssi != null && link.board != null) _SignalBadge(rssi),
          if (onSwitch != null)
            IconButton(
              tooltip: 'Switch board',
              icon: const Icon(Icons.swap_horiz),
              onPressed: onSwitch,
            ),
        ],
      ),
    );
  }
}

class _SignalBadge extends StatelessWidget {
  const _SignalBadge(this.rssi);

  final double rssi;

  @override
  Widget build(BuildContext context) {
    final proximity = Signal.proximity(rssi);
    final icon = switch (proximity) {
      Proximity.near => Icons.signal_cellular_alt,
      Proximity.around => Icons.signal_cellular_alt_2_bar,
      Proximity.far => Icons.signal_cellular_alt_1_bar,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: RadarColors.muted),
          const SizedBox(width: 4),
          Text(
            proximity.label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: RadarColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.link, required this.onChoose});

  final BoardLink link;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (link.status) {
      BoardStatus.looking => (
        'Looking for a board',
        'Power the ESP32 running the Hello board firmware. Its LED blinks '
            'blue while it waits for a phone.',
      ),
      BoardStatus.choosing => (
        'Several boards are nearby',
        'Pick yours by the last four characters of its name.',
      ),
      BoardStatus.connecting || BoardStatus.reconnecting => (
        'Connecting',
        link.problem ?? 'The board\'s LED blinks amber, then turns green.',
      ),
      BoardStatus.ready => (
        'Hold the BOOT button',
        link.info?.hasColor ?? true
            ? 'The circle grows and changes color with the board\'s LED.'
            : 'This board\'s LED has one color, so the colors show here.',
      ),
      BoardStatus.linkLost => (
        'Link lost',
        link.problem ?? 'Reconnecting by itself.',
      ),
      BoardStatus.notABoard => (
        'Not a bt_kit board',
        link.problem ?? 'Flash it with the Hello board firmware.',
      ),
    };
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            body,
            style: text.bodyMedium?.copyWith(color: RadarColors.muted),
            textAlign: TextAlign.center,
          ),
          if (link.status == BoardStatus.choosing) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onChoose, child: const Text('Choose')),
          ],
        ],
      ),
    );
  }
}

class _BlinkControls extends StatelessWidget {
  const _BlinkControls({
    required this.selected,
    required this.onSelect,
    required this.onBlink,
  });

  final BlinkColor selected;
  final ValueChanged<BlinkColor> onSelect;
  final VoidCallback? onBlink;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final color in BlinkColor.values)
                _Swatch(
                  color,
                  selected: color == selected,
                  onTap: () => onSelect(color),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: onBlink,
              icon: const Icon(Icons.flash_on),
              label: const Text('Blink'),
              style: FilledButton.styleFrom(
                textStyle: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color, {required this.selected, required this.onTap});

  final BlinkColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: color.label,
    child: Tooltip(
      message: color.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? RadarColors.text : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    ),
  );
}
