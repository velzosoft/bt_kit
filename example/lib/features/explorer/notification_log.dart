import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../bluetooth/hex.dart';
import 'characteristic_controller.dart';
import 'value_decoder.dart';
import 'value_log.dart';

/// The values a characteristic pushed since subscribing, newest first.
class NotificationLog extends StatelessWidget {
  const NotificationLog(this.controller, {super.key});

  final CharacteristicController controller;

  static const _rowHeight = 22.0;
  static const _visibleRows = 8;

  @override
  Widget build(BuildContext context) {
    final log = controller.log;
    final entries = log.entries.toList();
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: RadarColors.muted);
    final kept = log.received > log.length ? ', last ${log.length} kept' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${log.received} received$kept', style: muted),
            ),
            if (entries.isNotEmpty)
              TextButton(
                onPressed: controller.clearLog,
                child: const Text('Clear'),
              ),
          ],
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Waiting for the first value…', style: muted),
          )
        else
          SizedBox(
            height: min(entries.length, _visibleRows) * _rowHeight,
            child: ListView.builder(
              itemExtent: _rowHeight,
              itemCount: entries.length,
              itemBuilder: (context, index) => _LogRow(
                entries[index],
                ValueDecoder.characteristic(
                  controller.characteristic.uuid,
                  entries[index].bytes,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow(this.value, this.meaning);

  final TimedValue value;
  final String? meaning;

  @override
  Widget build(BuildContext context) {
    final style = RadarTheme.monospace.copyWith(fontSize: 12);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${clockTime(value.at)}  ',
            style: style.copyWith(color: RadarColors.muted),
          ),
          TextSpan(
            text: value.bytes.isEmpty ? 'empty' : value.bytes.toHex(max: 20),
            style: style.copyWith(color: RadarColors.text),
          ),
          if (meaning case final meaning?)
            TextSpan(
              text: '  $meaning',
              style: style.copyWith(color: RadarColors.sweep),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
