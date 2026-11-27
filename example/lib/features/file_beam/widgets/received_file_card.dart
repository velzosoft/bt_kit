import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/theme.dart';
import '../transfer/beam_reception.dart';
import '../transfer/transfer_units.dart';
import 'copy_record_button.dart';

/// A received file: the picture with a Share button, or for other data the
/// size, the verified checksum and the speed.
class ReceivedFileCard extends StatelessWidget {
  const ReceivedFileCard(this.file, {super.key});

  final ReceivedFile file;

  String get _summary =>
      '${TransferUnits.bytes(file.bytes.length)} received · checksum OK · '
      '${TransferUnits.kilobytesPerSecond(file.bytesPerSecond)} KB/s';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (file.isPng)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(file.bytes, fit: BoxFit.contain),
                ),
              )
            else
              const Icon(Icons.verified, size: 56, color: RadarColors.sweep),
            const SizedBox(height: 16),
            Text(
              _summary,
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${file.name} · ${TransferUnits.duration(file.elapsed)}',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: RadarColors.muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (file.isPng) _ShareButton(file),
                CopyRecordButton(
                  verb: 'received',
                  bytes: file.bytes.length,
                  elapsed: file.elapsed,
                  bytesPerSecond: file.bytesPerSecond,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton(this.file);

  final ReceivedFile file;

  /// The sender chose the name, so keep only safe characters.
  String get _fileName {
    final safe = file.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final named = safe.isEmpty ? 'beam' : safe;
    return named.toLowerCase().endsWith('.png') ? named : '$named.png';
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(file.bytes, mimeType: 'image/png')],
        fileNameOverrides: [_fileName],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: () => _share(context),
    icon: const Icon(Icons.ios_share),
    label: const Text('Share or save'),
  );
}
