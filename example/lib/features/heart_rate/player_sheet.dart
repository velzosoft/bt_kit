import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/heart_rate.dart';
import 'player.dart';
import 'player_palette.dart';
import 'showdown.dart';

Future<void> showPlayerSheet(
  BuildContext context,
  Showdown showdown,
  Player player,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => PlayerSheet(showdown: showdown, player: player),
);

/// Rename, recolor or remove a player, and see what their strap reports.
class PlayerSheet extends StatefulWidget {
  const PlayerSheet({super.key, required this.showdown, required this.player});

  final Showdown showdown;
  final Player player;

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  late final _name = TextEditingController(text: widget.player.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _rename(String value) {
    final name = value.trim();
    if (name.isNotEmpty) widget.player.name = name;
  }

  void _remove() {
    Navigator.of(context).pop();
    widget.showdown.remove(widget.player);
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                onChanged: _rename,
                maxLength: 20,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 4),
              _ColorPicker(
                selected: player.color,
                onSelect: (color) => player.color = color,
              ),
              const SizedBox(height: 20),
              _SensorDetails(player),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _remove,
                icon: const Icon(Icons.person_remove),
                label: const Text('Remove player'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelect});

  final Color selected;
  final ValueChanged<Color> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (final color in PlayerPalette.colors)
        Semantics(
          button: true,
          selected: color == selected,
          child: GestureDetector(
            onTap: () => onSelect(color),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color == selected
                      ? RadarColors.text
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _SensorDetails extends StatelessWidget {
  const _SensorDetails(this.player);

  final Player player;

  @override
  Widget build(BuildContext context) {
    final measurement = player.measurement;
    final baseline = player.baseline.value;
    final lastRr = measurement?.rrIntervals.lastOrNull;
    final energy = measurement?.energyExpended;
    final battery = player.battery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(player.sensorName, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _Detail('Status', player.statusText),
        _Detail('Battery', battery == null ? 'Not reported' : '$battery%'),
        _Detail('Skin contact', _contact(measurement?.contact)),
        _Detail(
          'Baseline',
          baseline == null ? 'Calibrating' : '${baseline.round()} BPM',
        ),
        if (lastRr != null)
          _Detail('Beat to beat', '${lastRr.inMilliseconds} ms'),
        if (energy != null) _Detail('Energy expended', '$energy kJ'),
      ],
    );
  }

  static String _contact(SensorContact? contact) => switch (contact) {
    SensorContact.detected => 'Detected',
    SensorContact.notDetected => 'Not detected: adjust the strap',
    SensorContact.unsupported || null => 'Not reported',
  };
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: style?.copyWith(color: RadarColors.muted),
            ),
          ),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}
