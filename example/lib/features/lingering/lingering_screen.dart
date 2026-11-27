import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/bluetooth_state_panel.dart';
import '../../app/theme.dart';
import '../../bluetooth/scanner.dart';
import '../../widgets/code_sheet.dart';
import 'lingering_code.dart';
import 'lingering_watch.dart';
import 'stay_detector.dart';
import 'widgets/changes_card.dart';
import 'widgets/experiment_notice.dart';
import 'widgets/limits_card.dart';
import 'widgets/stayed_device_tile.dart';

/// The "Things that stayed with you" experiment. It watches only while
/// this screen is open and forgets everything when it closes.
class LingeringScreen extends StatefulWidget {
  const LingeringScreen({super.key});

  @override
  State<LingeringScreen> createState() => _LingeringScreenState();
}

class _LingeringScreenState extends State<LingeringScreen> {
  late final Scanner _scanner;
  late final LingeringWatch _watch;

  @override
  void initState() {
    super.initState();
    _scanner = AppScope.of(context).scanner;
    _watch = LingeringWatch(_scanner);
  }

  @override
  void dispose() {
    _watch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Stayed with you'),
      actions: const [CodeButton(lingeringCode)],
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([_scanner, _watch]),
      builder: (context, _) => BluetoothStatePanel.needed(_scanner.status)
          ? BluetoothStatePanel(scanner: _scanner)
          : _body(),
    ),
  );

  Widget _body() {
    final text = Theme.of(context).textTheme;
    final flagged = _watch.flagged;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ExperimentNotice(),
        const SizedBox(height: 12),
        ChangesCard(watch: _watch, devicesAround: _scanner.count),
        const SizedBox(height: 24),
        Text('Things that stayed with you', style: text.titleSmall),
        const SizedBox(height: 8),
        if (flagged.isEmpty)
          _NothingYet(stayedOnce: _watch.unflaggedStayers)
        else
          for (final stayed in flagged)
            StayedDeviceTile(
              stayed: stayed,
              kind: _watch.kindOf(stayed.id),
              heardNow: _watch.heardNow(stayed.id),
            ),
        const SizedBox(height: 24),
        const LimitsCard(),
      ],
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet({required this.stayedOnce});

  final int stayedOnce;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final progress = stayedOnce == 0
        ? ''
        : ' So far, $stayedOnce '
              '${stayedOnce == 1 ? 'device has' : 'devices have'} stayed '
              'through a change or two.';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Nothing yet. A device is listed here once it stays with you '
          'through ${StayDetector.staysToFlag} changes within an hour.'
          '$progress',
          style: text.bodyMedium?.copyWith(color: RadarColors.muted),
        ),
      ),
    );
  }
}
