import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import 'permission_screens.dart';

enum _Stage { checking, welcome, denied, notDeclared, ready }

/// Shows the welcome screen until the Bluetooth permissions are granted,
/// then [home].
///
/// The system prompt appears only when the user taps Allow, never in a
/// loop. After a denial, the app waits for the user to change the
/// permission in the system settings and checks again on return.
class AppGate extends StatefulWidget {
  const AppGate({super.key, required this.home});

  final WidgetBuilder home;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  final _bt = BtKit.instance;
  late final AppLifecycleListener _lifecycle;
  var _stage = _Stage.checking;
  var _canAskAgain = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _recheck);
    _check(first: true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check({bool first = false}) async {
    final statuses = await _bt.checkPermissions();
    if (mounted) _apply(statuses, first: first);
  }

  Future<void> _recheck() async {
    if (_stage == _Stage.denied) await _check();
  }

  Future<void> _allow() async {
    final statuses = await _bt.requestPermissions();
    if (mounted) _apply(statuses, first: false);
  }

  void _apply(
    Map<BluetoothPermission, PermissionStatus> statuses, {
    required bool first,
  }) {
    final values = statuses.values;
    final askable = values.any(
      (s) =>
          s == PermissionStatus.notDetermined || s == PermissionStatus.denied,
    );
    setState(() {
      _canAskAgain = askable;
      _stage = switch (values) {
        _ when values.every((s) => s.isGranted) => _Stage.ready,
        _ when values.contains(PermissionStatus.notDeclared) =>
          _Stage.notDeclared,
        _ when first && askable => _Stage.welcome,
        _ => _Stage.denied,
      };
    });
  }

  @override
  Widget build(BuildContext context) => switch (_stage) {
    _Stage.checking => const Scaffold(),
    _Stage.welcome => WelcomeScreen(onAllow: _allow),
    _Stage.denied => PermissionDeniedScreen(
      onAskAgain: _canAskAgain ? _allow : null,
    ),
    _Stage.notDeclared => const NotDeclaredScreen(),
    _Stage.ready => widget.home(context),
  };
}
