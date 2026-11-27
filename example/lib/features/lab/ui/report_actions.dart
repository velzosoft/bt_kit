import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../model/lab_report.dart';
import '../model/test_result.dart';

/// The run's verdict, with the JSON report to share or copy.
class ReportActions extends StatelessWidget {
  const ReportActions({super.key, required this.report});

  final LabReport report;

  String get _verdict {
    if (report.passed) {
      return 'All ${report.results.length} tests passed';
    }
    return [
      for (final outcome in TestOutcome.values)
        if (report.count(outcome) > 0)
          '${report.count(outcome)} ${outcome.name}',
    ].join(' · ');
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(report.encode()),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: [report.fileName],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: report.encode()));
    messenger.showSnackBar(
      const SnackBar(content: Text('Report copied as JSON')),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(_verdict, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Builder(
              builder: (context) => FilledButton.tonalIcon(
                onPressed: () => _share(context),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share JSON'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy),
              label: const Text('Copy JSON'),
            ),
          ),
        ],
      ),
    ],
  );
}
