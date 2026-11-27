import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../bluetooth/scanner.dart';
import 'share_card.dart';

Future<void> showShareSheet(BuildContext context, Scanner scanner) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ShareSheet(ShareCardData.of(scanner)),
    );

/// Previews the share card, takes an optional caption and opens the system
/// share sheet.
class ShareSheet extends StatefulWidget {
  const ShareSheet(this.snapshot, {super.key});

  final ShareCardData snapshot;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final _caption = TextEditingController();
  var _sharing = false;

  ShareCardData get _card => widget.snapshot.withCaption(_caption.text);

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _share(Rect origin) async {
    setState(() => _sharing = true);
    try {
      final card = _card;
      final png = await renderShareCard(card);
      await SharePlus.instance.share(
        ShareParams(
          text: card.headline,
          files: [XFile.fromData(png, mimeType: 'image/png')],
          fileNameOverrides: const ['bluetooth-radar.png'],
          sharePositionOrigin: origin,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: AspectRatio(
              aspectRatio:
                  ShareCardPainter.size.width / ShareCardPainter.size.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListenableBuilder(
                  listenable: _caption,
                  builder: (_, _) =>
                      CustomPaint(painter: ShareCardPainter(_card)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _caption,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Caption',
            hintText: 'Where are you? For example, Heathrow T5',
          ),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (context) => FilledButton.icon(
            onPressed: _sharing
                ? null
                : () {
                    final box = context.findRenderObject()! as RenderBox;
                    _share(box.localToGlobal(Offset.zero) & box.size);
                  },
            icon: const Icon(Icons.ios_share),
            label: const Text('Share'),
          ),
        ),
      ],
    ),
  );
}
