import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/hex.dart';
import 'value_log.dart';

/// The last value of an attribute: what it means when known, its bytes in
/// hex, and when it arrived.
class ValueView extends StatelessWidget {
  const ValueView({super.key, required this.value, this.meaning});

  final TimedValue value;
  final String? meaning;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final bytes = value.bytes;
    final size = bytes.length == 1 ? '1 byte' : '${bytes.length} bytes';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meaning case final meaning?)
            Text(meaning, style: text.titleMedium),
          SelectableText(
            bytes.isEmpty ? 'Empty value' : bytes.toHex(),
            style: RadarTheme.monospace.copyWith(color: RadarColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            '$size at ${clockTime(value.at)}',
            style: text.bodySmall?.copyWith(color: RadarColors.muted),
          ),
        ],
      ),
    );
  }
}
