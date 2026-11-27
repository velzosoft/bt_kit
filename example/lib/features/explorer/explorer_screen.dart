import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../bluetooth/tracked_device.dart';
import '../../widgets/code_sheet.dart';
import '../../widgets/kind_style.dart';
import 'connection_views.dart';
import 'explorer_code.dart';
import 'explorer_controller.dart';
import 'gatt_view.dart';

/// The GATT explorer: connects to a device and lists its services, with
/// read, write and subscribe on every characteristic. Leaving disconnects.
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key, required this.device});

  final TrackedDevice device;

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  late final _explorer = ExplorerController(widget.device.peripheral);

  @override
  void initState() {
    super.initState();
    unawaited(_explorer.connect());
  }

  @override
  void dispose() {
    _explorer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          KindAvatar(widget.device.kind, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.device.displayName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: const [CodeButton(explorerCode)],
    ),
    body: ListenableBuilder(
      listenable: _explorer,
      builder: (context, _) => switch (_explorer.phase) {
        ExplorerPhase.connecting || ExplorerPhase.discovering => ConnectingView(
          explorer: _explorer,
          name: widget.device.displayName,
        ),
        ExplorerPhase.failed => FailedView(_explorer),
        ExplorerPhase.ready => GattView(_explorer),
      },
    ),
  );
}
