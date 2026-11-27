import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../bluetooth/tracked_device.dart';
import 'board_link.dart';

Future<void> showBoardPicker(BuildContext context, BoardLink link) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BoardPicker(link: link),
    );

/// The boards nearby, from the app's shared scan, strongest signal first.
/// Each one's name ends in the last four hex digits of its address, as in
/// its serial log.
class BoardPicker extends StatelessWidget {
  const BoardPicker({super.key, required this.link});

  final BoardLink link;

  void _choose(BuildContext context, TrackedDevice board) {
    link.choose(board);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = AppScope.of(context).scanner;
    final text = Theme.of(context).textTheme;
    return FractionallySizedBox(
      heightFactor: 0.6,
      child: ListenableBuilder(
        listenable: Listenable.merge([scanner, link]),
        builder: (context, _) {
          final boards = link.nearby;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Choose a board', style: text.titleMedium),
                    Text(
                      'The closest board is first. A board stops '
                      'advertising while a phone is connected to it.',
                      style: text.bodySmall?.copyWith(color: RadarColors.muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: boards.isEmpty
                    ? const _Searching()
                    : ListView(
                        children: [
                          for (final board in boards)
                            _BoardTile(
                              board,
                              current: board.id == link.board?.id,
                              onTap: () => _choose(context, board),
                            ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile(this.board, {required this.current, required this.onTap});

  final TrackedDevice board;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: const Icon(Icons.developer_board, color: RadarColors.sweep),
    title: Text(board.displayName),
    subtitle: Text('${board.proximity.label} · ${board.rssi.round()} dBm'),
    trailing: current
        ? const Icon(Icons.check, color: RadarColors.sweep)
        : const Icon(Icons.chevron_right),
  );
}

class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(height: 16),
        Text(
          'Looking for boards…',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    ),
  );
}
