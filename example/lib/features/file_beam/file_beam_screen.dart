import 'package:material_ui/material_ui.dart';

import '../../widgets/code_sheet.dart';
import 'file_beam_code.dart';
import 'widgets/beam_intro.dart';
import 'widgets/receive_view.dart';
import 'widgets/send_view.dart';

enum _Role { send, receive }

/// Sends a picture between two phones over an L2CAP channel. Each role's
/// view owns its Bluetooth resources, so switching roles or leaving the
/// screen releases them.
class FileBeamScreen extends StatefulWidget {
  const FileBeamScreen({super.key});

  @override
  State<FileBeamScreen> createState() => _FileBeamScreenState();
}

class _FileBeamScreenState extends State<FileBeamScreen> {
  _Role? _role;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('File beam'),
      actions: const [CodeButton(fileBeamCode)],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SegmentedButton<_Role>(
            segments: const [
              ButtonSegment(
                value: _Role.send,
                icon: Icon(Icons.upload),
                label: Text('Send'),
              ),
              ButtonSegment(
                value: _Role.receive,
                icon: Icon(Icons.download),
                label: Text('Receive'),
              ),
            ],
            selected: {?_role},
            emptySelectionAllowed: true,
            onSelectionChanged: (selection) =>
                setState(() => _role = selection.firstOrNull),
          ),
        ),
        Expanded(
          child: switch (_role) {
            null => const BeamIntro(),
            _Role.send => const SendView(),
            _Role.receive => const ReceiveView(),
          },
        ),
      ],
    ),
  );
}
