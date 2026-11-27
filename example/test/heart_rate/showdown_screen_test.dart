import 'package:bt_radar/app/theme.dart';
import 'package:bt_radar/features/heart_rate/showdown.dart';
import 'package:bt_radar/features/heart_rate/showdown_screen.dart';
import 'package:bt_radar/features/heart_rate/streamer_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget home) => MaterialApp(theme: RadarTheme.dark, home: home);

void main() {
  testWidgets('invites players before anyone joins', (tester) async {
    await tester.pumpWidget(_app(const ShowdownScreen()));

    expect(find.text('Who keeps their cool?'), findsOneWidget);
    expect(find.textContaining('Apple Watch'), findsOneWidget);
    final streamer = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.live_tv),
    );
    expect(streamer.onPressed, isNull);
  });

  testWidgets('shows the code behind the screen', (tester) async {
    await tester.pumpWidget(_app(const ShowdownScreen()));

    await tester.tap(find.byTooltip('Show code'));
    await tester.pumpAndSettle();

    expect(find.textContaining('several live connections'), findsOneWidget);
  });

  testWidgets('streamer mode keys out a chroma-green background', (
    tester,
  ) async {
    final showdown = Showdown();
    addTearDown(showdown.dispose);
    await tester.pumpWidget(_app(StreamerScreen(showdown: showdown)));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, RadarColors.chromaKey);

    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
