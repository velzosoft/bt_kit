import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../app/bluetooth_state_panel.dart';
import '../../app/theme.dart';
import '../../bluetooth/scanner.dart';
import '../../bluetooth/tracked_device.dart';
import '../../widgets/code_sheet.dart';
import '../lab/lab_screen.dart';
import '../share/share_sheet.dart';
import 'device_list_view.dart';
import 'device_sheet.dart';
import 'radar_code.dart';
import 'radar_header.dart';
import 'radar_view.dart';

/// The home screen: every nearby device as a blip on a radar, or as a list.
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  var _showList = false;
  String? _selectedId;

  Future<void> _select(TrackedDevice device) async {
    setState(() => _selectedId = device.id);
    await showDeviceSheet(context, device);
    if (mounted) setState(() => _selectedId = null);
  }

  void _openLab() =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const LabScreen()));

  @override
  Widget build(BuildContext context) {
    final scanner = AppScope.of(context).scanner;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _openLab,
          child: const Text('Bluetooth Radar'),
        ),
        actions: [
          IconButton(
            tooltip: _showList ? 'Show radar' : 'Show list',
            icon: Icon(_showList ? Icons.radar : Icons.view_list),
            onPressed: () => setState(() => _showList = !_showList),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share),
            onPressed: () => showShareSheet(context, scanner),
          ),
          const CodeButton(radarCode),
        ],
      ),
      body: ListenableBuilder(
        listenable: scanner,
        builder: (context, _) => BluetoothStatePanel.needed(scanner.status)
            ? BluetoothStatePanel(scanner: scanner)
            : _body(scanner),
      ),
    );
  }

  Widget _body(Scanner scanner) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RadarHeader(count: scanner.count, breakdown: scanner.breakdown),
      Expanded(
        child: _showList
            ? DeviceListView(devices: scanner.bySignal, onSelect: _select)
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: RadarView(
                          scanner: scanner,
                          onSelect: _select,
                          selectedId: _selectedId,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      scanner.count == 0
                          ? 'Listening for devices…'
                          : 'Tap a blip to see what it is',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: RadarColors.muted),
                    ),
                  ),
                ],
              ),
      ),
    ],
  );
}
