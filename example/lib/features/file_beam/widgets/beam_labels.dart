import 'package:material_ui/material_ui.dart';

/// A spinner with what is happening.
class BeamBusy extends StatelessWidget {
  const BeamBusy(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
}

/// The heading above a transfer, such as "Sending bluetooth-radar.png".
class BeamTitle extends StatelessWidget {
  const BeamTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}
