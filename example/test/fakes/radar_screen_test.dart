import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/testing.dart';
import 'package:bt_radar/app/app_scope.dart';
import 'package:bt_radar/app/theme.dart';
import 'package:bt_radar/bluetooth/scanner.dart';
import 'package:bt_radar/features/radar/radar_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late FakeBluetooth bluetooth;

  setUp(() {
    bluetooth = FakeBluetooth.install()
      ..add(
        FakePeripheral(
          id: 'AA:BB:CC:DD:EE:01',
          advertisement: const AdvertisementData(localName: 'Kitchen speaker'),
          rssi: -48,
        ),
      )
      ..add(
        FakePeripheral(
          id: 'AA:BB:CC:DD:EE:02',
          advertisement: AdvertisementData(
            localName: 'Polar H10',
            serviceUuids: [BluetoothUuid.short(0x180d)],
          ),
          rssi: -71,
        ),
      );
  });

  tearDown(FakeBluetooth.uninstall);

  Future<Scanner> pumpRadar(WidgetTester tester) async {
    final scanner = Scanner()..enable();
    await tester.pumpWidget(
      AppScope(
        scanner: scanner,
        child: MaterialApp(theme: RadarTheme.dark, home: const RadarScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    return scanner;
  }

  Future<void> finish(WidgetTester tester, Scanner scanner) async {
    await tester.pumpWidget(const SizedBox());
    scanner.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('lists the devices the scan finds', (tester) async {
    final scanner = await pumpRadar(tester);

    await tester.tap(find.byTooltip('Show list'));
    await tester.pump();

    expect(find.text('Kitchen speaker'), findsWidgets);
    expect(find.text('Polar H10'), findsWidgets);
    expect(scanner.count, 2);
    await finish(tester, scanner);
  });

  testWidgets('turns Bluetooth on from the panel and starts scanning', (
    tester,
  ) async {
    bluetooth.adapterState = AdapterState.poweredOff;
    final scanner = await pumpRadar(tester);
    expect(find.text('Bluetooth is off'), findsOneWidget);

    await tester.tap(find.text('Turn on Bluetooth'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Bluetooth is off'), findsNothing);
    expect(scanner.count, 2);
    await finish(tester, scanner);
  });

  testWidgets('asks for the permission when it is missing', (tester) async {
    bluetooth.permissions[BluetoothPermission.scan] =
        PermissionStatus.permanentlyDenied;
    final scanner = await pumpRadar(tester);

    expect(find.text('Bluetooth permission is off'), findsOneWidget);
    await finish(tester, scanner);
  });
}
