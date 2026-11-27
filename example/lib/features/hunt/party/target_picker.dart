import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../bluetooth/tracked_device.dart';
import '../../../widgets/kind_style.dart';
import 'fingerprint_hint.dart';
import 'target_matcher.dart';

/// The device a seeker's phone takes for the target, and how sure it is.
final class TargetChoice {
  const TargetChoice({
    required this.matches,
    required this.nearby,
    required this.selected,
  });

  /// Likely targets, best first.
  final List<TargetMatch<TrackedDevice>> matches;

  /// Every device heard, strongest first, for picking by hand.
  final List<TrackedDevice> nearby;

  final TrackedDevice? selected;

  MatchConfidence get confidence {
    for (final match in matches) {
      if (match.device.id == selected?.id) return match.confidence;
    }
    return MatchConfidence.none;
  }

  bool get isAmbiguous =>
      TargetMatch.isAmbiguous(matches) &&
      matches.first.device.id == selected?.id;
}

/// Shows the chosen target, with a button to pick another.
class TargetPicker extends StatelessWidget {
  const TargetPicker({super.key, required this.choice, required this.onPick});

  final TargetChoice choice;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final selected = choice.selected;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: selected == null
            ? const Icon(Icons.search, color: RadarColors.muted)
            : KindAvatar(selected.kind),
        title: Text(selected?.displayName ?? 'Not heard yet'),
        subtitle: Text(_describe(selected)),
        trailing: TextButton(
          onPressed: () => _showSheet(context),
          child: const Text('Change'),
        ),
      ),
    );
  }

  String _describe(TrackedDevice? selected) {
    if (selected == null) {
      return 'Nothing nearby matches the hider’s device yet.';
    }
    final label = _label(choice.confidence);
    return choice.isAmbiguous ? '$label · others look alike' : label;
  }

  void _showSheet(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.75,
      child: _TargetSheet(
        choice: choice,
        onPick: (id) {
          Navigator.of(context).pop();
          onPick(id);
        },
      ),
    ),
  );
}

class _TargetSheet extends StatelessWidget {
  const _TargetSheet({required this.choice, required this.onPick});

  final TargetChoice choice;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final matched = {for (final match in choice.matches) match.device.id};
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text('Which device is the target?', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          unnamedDevicesNote,
          style: text.bodySmall?.copyWith(color: RadarColors.muted),
        ),
        if (choice.matches.isNotEmpty) const _Section('Matches'),
        for (final match in choice.matches)
          _DeviceTile(
            match.device,
            label: _label(match.confidence),
            selected: match.device.id == choice.selected?.id,
            onTap: () => onPick(match.device.id),
          ),
        const _Section('Other devices nearby'),
        for (final device in choice.nearby.where(
          (d) => !matched.contains(d.id),
        ))
          _DeviceTile(
            device,
            label: device.proximity.label,
            selected: device.id == choice.selected?.id,
            onTap: () => onPick(device.id),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 4),
    child: Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: RadarColors.muted, letterSpacing: 1.2),
    ),
  );
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile(
    this.device, {
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TrackedDevice device;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: KindAvatar(device.kind, size: 36),
    title: Text(device.displayName),
    subtitle: Text('$label · ${device.category.reason}'),
    trailing: selected
        ? const Icon(Icons.check, color: RadarColors.sweep)
        : null,
    onTap: onTap,
  );
}

String _label(MatchConfidence confidence) => switch (confidence) {
  MatchConfidence.certain => 'Sure match',
  MatchConfidence.strong => 'Likely match',
  MatchConfidence.weak => 'Possible match',
  MatchConfidence.none => 'Your pick',
};
