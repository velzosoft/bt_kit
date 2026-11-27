import 'package:material_ui/material_ui.dart';

import '../features/heart_rate/showdown_screen.dart';
import '../features/radar/radar_screen.dart';
import 'app_scope.dart';
import 'more_screen.dart';

/// The three top-level tabs. Each keeps its state while hidden, and the
/// shared scan keeps running across them.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _tabs = [RadarScreen(), ShowdownScreen(), MoreScreen()];

  var _tab = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context).scanner.enable();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        for (final (i, tab) in _tabs.indexed)
          TickerMode(enabled: i == _tab, child: tab),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (tab) => setState(() => _tab = tab),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
        NavigationDestination(
          icon: Icon(Icons.monitor_heart_outlined),
          selectedIcon: Icon(Icons.monitor_heart),
          label: 'Showdown',
        ),
        NavigationDestination(
          icon: Icon(Icons.apps_outlined),
          selectedIcon: Icon(Icons.apps),
          label: 'More',
        ),
      ],
    ),
  );
}
