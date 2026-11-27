import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import 'write_draft.dart';

typedef WriteDialogResult = ({List<int> bytes, bool withResponse});

typedef WriteLimit = int Function({required bool withResponse});

Future<WriteDialogResult?> showWriteDialog(
  BuildContext context, {
  required String name,
  required CharacteristicProperties properties,
  required WriteLimit limit,
}) => showDialog<WriteDialogResult>(
  context: context,
  builder: (_) => WriteDialog(name: name, properties: properties, limit: limit),
);

/// Asks for a value as hex or text, and for the write type when the
/// characteristic supports both.
class WriteDialog extends StatefulWidget {
  const WriteDialog({
    super.key,
    required this.name,
    required this.properties,
    required this.limit,
  });

  final String name;
  final CharacteristicProperties properties;
  final WriteLimit limit;

  @override
  State<WriteDialog> createState() => _WriteDialogState();
}

class _WriteDialogState extends State<WriteDialog> {
  final _input = TextEditingController();
  var _format = WriteFormat.hex;
  late var _withResponse = widget.properties.write;

  WriteDraft get _draft => WriteDraft(_input.text, _format);

  int get _limit => widget.limit(withResponse: _withResponse);

  bool get _offersBoth =>
      widget.properties.write && widget.properties.writeWithoutResponse;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _setFormat(WriteFormat format) => setState(() {
    _input.text = _draft.convertTo(format).input;
    _format = format;
  });

  void _submit() {
    final draft = _draft;
    final bytes = draft.bytes;
    if (bytes == null || draft.problem(_limit) != null) return;
    Navigator.of(context).pop((bytes: bytes, withResponse: _withResponse));
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final limit = _limit;
    final problem = draft.problem(limit);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: RadarColors.muted);
    final hex = _format == WriteFormat.hex;
    return AlertDialog(
      title: Text('Write ${widget.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<WriteFormat>(
              segments: const [
                ButtonSegment(value: WriteFormat.hex, label: Text('Hex')),
                ButtonSegment(value: WriteFormat.text, label: Text('Text')),
              ],
              selected: {_format},
              onSelectionChanged: (selected) => _setFormat(selected.single),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _input,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 1,
              maxLines: 4,
              style: hex ? RadarTheme.monospace : null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: hex ? '01 FF 3C' : 'Hello',
                errorText: _input.text.isEmpty ? null : problem,
                counterText: '${draft.bytes?.length ?? '?'} of $limit bytes',
              ),
            ),
            const SizedBox(height: 16),
            if (_offersBoth)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('With response')),
                  ButtonSegment(value: false, label: Text('Without')),
                ],
                selected: {_withResponse},
                onSelectionChanged: (selected) =>
                    setState(() => _withResponse = selected.single),
              )
            else
              Text(
                _withResponse
                    ? 'Written with response'
                    : 'Written without response',
                style: muted,
              ),
            if (!_withResponse) ...[
              const SizedBox(height: 8),
              Text(
                'The device does not confirm a write without response.',
                style: muted,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem == null ? _submit : null,
          child: const Text('Write'),
        ),
      ],
    );
  }
}
