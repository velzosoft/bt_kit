import 'package:material_ui/material_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/code_sheet.dart';
import 'lab_code.dart';
import 'peripheral/reference_peripheral.dart';
import 'ui/lab_controller.dart';
import 'ui/run_tab.dart';
import 'ui/serve_tab.dart';

/// The hidden Lab: bt_kit's on-device test suite, and this phone as the
/// reference peripheral for a Lab on another phone.
class LabScreen extends StatefulWidget {
  const LabScreen({super.key});

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  late final _controller = LabController(AppScope.of(context).scanner);
  final _reference = ReferencePeripheral();

  @override
  void dispose() {
    _controller.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Lab'),
        actions: const [CodeButton(labCode)],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Run tests'),
            Tab(text: 'Be the reference'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          RunTab(controller: _controller),
          ServeTab(peripheral: _reference),
        ],
      ),
    ),
  );
}
