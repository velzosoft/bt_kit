import 'package:bt_radar/features/hunt/hunt_signal.dart';
import 'package:bt_radar/features/hunt/signal_meter.dart';
import 'package:bt_radar/features/hunt/signal_trend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpMeter(WidgetTester tester, HuntReading reading) async {
    final clicks = ValueNotifier(0);
    addTearDown(clicks.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 300,
            child: SignalMeter(reading: reading, clicks: clicks),
          ),
        ),
      ),
    );
    clicks.value++;
    await tester.pumpAndSettle();
  }

  testWidgets('shows the trend while the target is heard', (tester) async {
    await pumpMeter(
      tester,
      const HuntReading(
        status: HuntStatus.live,
        rssi: -50,
        trend: Trend.warmer,
      ),
    );
    expect(find.text('Warmer'), findsOneWidget);
  });

  testWidgets('says when the signal is lost', (tester) async {
    await pumpMeter(
      tester,
      const HuntReading(status: HuntStatus.lost, silence: Duration(seconds: 6)),
    );
    expect(find.text('Signal lost'), findsOneWidget);
  });

  testWidgets('listens before the first advertisement', (tester) async {
    await pumpMeter(tester, const HuntReading.searching());
    expect(find.text('Listening…'), findsOneWidget);
  });
}
