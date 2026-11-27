import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/testing.dart';
import 'package:bt_radar/app/app_scope.dart';
import 'package:bt_radar/app/theme.dart';
import 'package:bt_radar/bluetooth/scanner.dart';
import 'package:bt_radar/features/board/board_protocol.dart';
import 'package:bt_radar/features/board/board_screen.dart';
import 'package:bt_radar/features/board/press_circle.dart';
import 'package:bt_radar/features/board/virtual_led.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_board.dart';

void main() {
  late FakeBluetooth bluetooth;

  setUp(() => bluetooth = FakeBluetooth.install());

  tearDown(FakeBluetooth.uninstall);

  Future<Scanner> pumpScreen(WidgetTester tester) async {
    final scanner = Scanner()..enable();
    await tester.pumpWidget(
      AppScope(
        scanner: scanner,
        child: MaterialApp(theme: RadarTheme.dark, home: const BoardScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    return scanner;
  }

  Future<FakeBoard> pumpWithBoard(
    WidgetTester tester, {
    Duration? heldFor,
  }) async {
    final board = FakeBoard(heldFor: heldFor);
    bluetooth.add(board.peripheral);
    addTearDown((await pumpScreen(tester)).dispose);
    return board;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  double circleRadius(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(find.byKey(PressCircle.paintKey));
    return (paint.painter! as PressCirclePainter).radius;
  }

  testWidgets('connects to the only board and subscribes', (tester) async {
    final board = await pumpWithBoard(tester);

    expect(find.text('bt_kit Board 296A'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(board.isSubscribedToLed, isTrue);
    expect(board.isSubscribedToButton, isTrue);
    expect(board.peripheral.connectionPriority, ConnectionPriority.high);
    expect(find.textContaining('LED has one color'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('shows the LED the board reports', (tester) async {
    final board = await pumpWithBoard(tester);
    LedState? led() => tester.widget<VirtualLed>(find.byType(VirtualLed)).state;
    expect(led()?.state, BoardState.connected);

    await board.showLed([0x03, 0x01, 0x00, 0xff, 0x00, 0x00]);
    await tester.pump();

    expect(led()?.state, BoardState.ready);
    expect(led()?.pattern, LedPattern.solid);
    await finish(tester);
  });

  testWidgets('a press draws a circle that grows', (tester) async {
    final board = await pumpWithBoard(tester);
    expect(circleRadius(tester), 0);

    await board.press();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final start = circleRadius(tester);
    await tester.pump(const Duration(seconds: 1));
    final later = circleRadius(tester);

    expect(start, greaterThanOrEqualTo(PressGeometry.minRadius));
    expect(later, greaterThan(start));
    expect(find.text('Hold the BOOT button'), findsNothing);
    await finish(tester);
  });

  testWidgets('a release pops the circle and shows the board\'s time', (
    tester,
  ) async {
    final board = await pumpWithBoard(tester);
    await board.press();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    await board.release(const Duration(milliseconds: 2400));
    await tester.pump();

    expect(find.text('2.4 s'), findsOneWidget);
    expect(find.text('press 1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(circleRadius(tester), 0);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('2.4 s'), findsNothing);
    expect(find.text('Hold the BOOT button'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('shows a hold already in progress at its size', (tester) async {
    await pumpWithBoard(tester, heldFor: const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 16));

    final size = tester.getSize(find.byKey(PressCircle.paintKey));
    expect(
      circleRadius(tester),
      closeTo(size.shortestSide / 2, size.shortestSide * 0.04),
    );
    await finish(tester);
  });

  testWidgets('Blink sends three flashes in the chosen color', (tester) async {
    final board = await pumpWithBoard(tester);

    await tester.tap(find.text('Blink'));
    await tester.pump();
    await tester.tap(find.byTooltip('Magenta'));
    await tester.pump();
    await tester.tap(find.text('Blink'));
    await tester.pump();

    expect(board.commands, [
      [0x01, 0xff, 0xff, 0xff, 0x03],
      [0x01, 0xff, 0x00, 0xff, 0x03],
    ]);
    await finish(tester);
  });

  testWidgets('a refused blink shows a short message', (tester) async {
    await pumpWithBoard(tester);
    bluetooth.failNext(GattError.valueNotAllowed);

    await tester.tap(find.text('Blink'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('refused the request'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a drop while held says Link lost, then reconnects', (
    tester,
  ) async {
    final board = await pumpWithBoard(tester);
    await board.press();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    board.peripheral.disconnect();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Link lost'), findsWidgets);
    expect(circleRadius(tester), 0);
    final blink = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Blink'),
    );
    expect(blink.onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Ready'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('lets the user pick when several boards are nearby', (
    tester,
  ) async {
    final first = FakeBoard(rssi: -70);
    final second = FakeBoard(id: 'E4:0A:C4:07:31:B2', rssi: -45);
    bluetooth
      ..add(first.peripheral)
      ..add(second.peripheral);
    addTearDown((await pumpScreen(tester)).dispose);
    await settle(tester);

    expect(find.text('Choose a board'), findsWidgets);
    final names = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(names, ['bt_kit Board 31B2', 'bt_kit Board 296A']);

    await tester.tap(find.text('bt_kit Board 31B2'));
    await settle(tester);

    expect(find.text('Ready'), findsOneWidget);
    expect(second.isSubscribedToButton, isTrue);
    expect(first.peripheral.isConnected, isFalse);
    await finish(tester);
  });

  testWidgets('disconnects when the screen closes', (tester) async {
    final board = await pumpWithBoard(tester);
    expect(board.peripheral.isConnected, isTrue);

    await finish(tester);

    expect(board.peripheral.isConnected, isFalse);
  });

  testWidgets('shows the code behind the screen', (tester) async {
    await pumpWithBoard(tester);

    await tester.tap(find.byTooltip('Show code'));
    await settle(tester);

    expect(find.textContaining('two subscriptions'), findsOneWidget);
    await tester.tap(find.text('Android'));
    await settle(tester);
    expect(find.textContaining('setCharacteristicNotification'), findsWidgets);
    await finish(tester);
  });
}
