import 'package:material_ui/material_ui.dart';

import '../bluetooth/scanner.dart';
import 'app_scope.dart';
import 'home_screen.dart';
import 'onboarding/app_gate.dart';
import 'theme.dart';

class RadarApp extends StatefulWidget {
  const RadarApp({super.key});

  @override
  State<RadarApp> createState() => _RadarAppState();
}

class _RadarAppState extends State<RadarApp> {
  final _scanner = Scanner();

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    scanner: _scanner,
    child: MaterialApp(
      title: 'Bluetooth Radar',
      debugShowCheckedModeBanner: false,
      theme: RadarTheme.dark,
      home: AppGate(home: (_) => const HomeScreen()),
    ),
  );
}
