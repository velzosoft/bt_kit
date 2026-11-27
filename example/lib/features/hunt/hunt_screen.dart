import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/bluetooth_state_panel.dart';
import '../../app/theme.dart';
import '../../bluetooth/tracked_device.dart';
import '../../widgets/code_sheet.dart';
import '../../bluetooth/beacon_code.dart';
import 'feedback_toggles.dart';
import 'hunt_code.dart';
import 'hunt_controller.dart';
import 'hunt_view.dart';
import 'party/party_host_screen.dart';
import 'target_header.dart';

/// A Geiger counter for one device: it clicks and vibrates faster as the
/// signal gets stronger.
class HuntScreen extends StatefulWidget {
  const HuntScreen({super.key, required this.device});

  final TrackedDevice device;

  @override
  State<HuntScreen> createState() => _HuntScreenState();
}

class _HuntScreenState extends State<HuntScreen> {
  late final _controller = HuntController(
    targetId: widget.device.id,
    scanner: AppScope.of(context).scanner,
  );

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startParty() async {
    _controller.pause();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PartyHostScreen(target: widget.device),
      ),
    );
    if (mounted) _controller.resume();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = _controller.scanner;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hunt'),
        actions: [
          FeedbackToggles(_controller.clicker),
          const CodeButton(huntCode),
        ],
      ),
      body: ListenableBuilder(
        listenable: scanner,
        builder: (context, _) => BluetoothStatePanel.needed(scanner.status)
            ? BluetoothStatePanel(scanner: scanner)
            : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final device = widget.device;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TargetHeader(
              kind: device.kind,
              title: switch (BeaconCode.read(device.data)) {
                final code? => 'Beacon $code',
                null => device.displayName,
              },
              detail: '${device.kind.label} · ${device.category.reason}',
            ),
            Expanded(child: HuntView(controller: _controller)),
            Text(
              'Walk slowly and pause often. Your body and walls weaken the '
              'signal, so turn around too.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: RadarColors.muted),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _startParty,
              icon: const Icon(Icons.celebration_outlined),
              label: const Text('Start a party'),
            ),
          ],
        ),
      ),
    );
  }
}
