import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../transfer/transfer_units.dart';

/// Copies a one-line record of a finished transfer, so that throughput can
/// be logged when testing between phones.
class CopyRecordButton extends StatelessWidget {
  const CopyRecordButton({
    super.key,
    required this.verb,
    required this.bytes,
    required this.elapsed,
    required this.bytesPerSecond,
  });

  /// `sent` or `received`.
  final String verb;
  final int bytes;
  final Duration elapsed;
  final double bytesPerSecond;

  String get record =>
      'File beam on ${Platform.isIOS ? 'iOS' : 'Android'}: $verb '
      '${TransferUnits.bytes(bytes)} in ${TransferUnits.duration(elapsed)}, '
      '${TransferUnits.kilobytesPerSecond(bytesPerSecond)} KB/s';

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: record));
    messenger.showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _copy(context),
    icon: const Icon(Icons.copy, size: 18),
    label: const Text('Copy numbers'),
  );
}
