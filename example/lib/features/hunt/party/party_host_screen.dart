import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../app/system_settings.dart';
import '../../../bluetooth/tracked_device.dart';
import '../../../widgets/code_sheet.dart';
import '../message_panel.dart';
import 'party_code.dart';
import 'party_host.dart';
import 'party_host_views.dart';
import 'party_protocol.dart';
import 'target_fingerprint.dart';

/// The hider's phone: names the target, hosts the party and runs rounds.
class PartyHostScreen extends StatefulWidget {
  const PartyHostScreen({super.key, required this.target});

  final TrackedDevice target;

  @override
  State<PartyHostScreen> createState() => _PartyHostScreenState();
}

class _PartyHostScreenState extends State<PartyHostScreen> {
  final _name = TextEditingController();
  late final _fingerprint = TargetFingerprint.of(
    id: widget.target.id,
    data: widget.target.data,
    idsAreAddresses: Platform.isAndroid,
  );
  PartyHost? _host;

  @override
  void dispose() {
    _name.dispose();
    _host?.dispose();
    super.dispose();
  }

  void _open() {
    final name = PartyGame.cleanName(_name.text);
    if (name.isEmpty || _host != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _host = PartyHost(name: name, target: _fingerprint));
    _host!.open();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host a party'),
        actions: const [CodeButton(partyCode)],
      ),
      body: host == null
          ? HostSetupView(
              target: widget.target,
              fingerprint: _fingerprint,
              name: _name,
              onOpen: _open,
            )
          : ListenableBuilder(
              listenable: host,
              builder: (context, _) => _stage(host),
            ),
    );
  }

  Widget _stage(PartyHost host) => switch (host.status) {
    HostStatus.opening => const MessagePanel.busy('Opening the party…'),
    HostStatus.needsPermission => MessagePanel(
      icon: Icons.lock_outline,
      title: 'Bluetooth permission needed',
      body: host.message ?? '',
      primary: ('Open settings', SystemSettings.openAppSettings),
      secondary: ('Try again', host.open),
    ),
    HostStatus.unsupported => MessagePanel(
      icon: Icons.bluetooth_disabled,
      title: 'This phone cannot host',
      body: host.message ?? '',
    ),
    HostStatus.failed => MessagePanel(
      icon: Icons.error_outline,
      title: 'The party did not open',
      body: host.message ?? '',
      primary: ('Try again', host.open),
    ),
    HostStatus.open => switch (host.game.phase) {
      PartyPhase.go => HostRaceView(host: host),
      PartyPhase.finished => HostResultView(host: host),
      PartyPhase.lobby || PartyPhase.closed => HostLobbyView(host: host),
    },
  };
}
