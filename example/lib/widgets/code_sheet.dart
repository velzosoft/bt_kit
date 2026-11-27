import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import 'dart_highlighter.dart';

/// The bt_kit code behind a screen: the Layer 2 call, and the Layer 1 calls
/// it makes on each platform.
final class CodeSample {
  const CodeSample({
    required this.title,
    required this.layer2,
    required this.android,
    required this.ios,
  });

  final String title;
  final String layer2;
  final String android;
  final String ios;
}

/// The `</>` button that opens [sample] in a sheet.
class CodeButton extends StatelessWidget {
  const CodeButton(this.sample, {super.key});

  final CodeSample sample;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Show code',
    icon: const Icon(Icons.code),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CodeSheet(sample),
    ),
  );
}

class CodeSheet extends StatelessWidget {
  const CodeSheet(this.sample, {super.key});

  final CodeSample sample;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: 0.85,
    child: DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              sample.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: 'Layer 2'),
              Tab(text: 'Android'),
              Tab(text: 'iOS'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CodeView(sample.layer2, library: 'package:bt_kit/bt_kit.dart'),
                _CodeView(
                  sample.android,
                  library: 'package:bt_kit/android.dart',
                ),
                _CodeView(sample.ios, library: 'package:bt_kit/ios.dart'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CodeView extends StatelessWidget {
  const _CodeView(this.code, {required this.library});

  final String code;
  final String library;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "import '$library';",
                style: RadarTheme.monospace.copyWith(color: RadarColors.muted),
              ),
            ),
            _CopyButton(code),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText.rich(
              DartHighlighter.highlight(
                code.trim(),
                RadarTheme.monospace.copyWith(color: RadarColors.text),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _CopyButton extends StatefulWidget {
  const _CopyButton(this.text);

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  var _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text.trim()));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Copy',
    onPressed: _copy,
    icon: Icon(_copied ? Icons.check : Icons.copy, size: 20),
  );
}
