import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/testing.dart';
import 'package:bt_radar/app/theme.dart';
import 'package:bt_radar/bluetooth/tracked_device.dart';
import 'package:bt_radar/features/explorer/explorer_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _id = 'C4:7C:8D:6A:12:34';

void main() {
  late FakeBluetooth bluetooth;
  late FakePeripheral sensor;
  late LocalCharacteristic level;

  setUp(() {
    bluetooth = FakeBluetooth.install();
    level = LocalCharacteristic(
      BluetoothUuid.short(0x2a19),
      properties: const CharacteristicProperties.of(read: true),
      value: [87],
    );
    sensor = FakePeripheral(
      id: _id,
      name: 'Sensor',
      services: [
        LocalService(BluetoothUuid.short(0x180f), [level]),
      ],
    );
    bluetooth.add(sensor);
  });

  tearDown(FakeBluetooth.uninstall);

  Future<void> pumpExplorer(WidgetTester tester) async {
    final peripheral = await BtKit.instance.peripheral(_id);
    final device = TrackedDevice(
      Advertisement(
        peripheral: peripheral!,
        rssi: -50,
        data: const AdvertisementData(localName: 'Sensor'),
        receivedAt: DateTime.now(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: RadarTheme.dark,
        home: ExplorerScreen(device: device),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('connects, discovers and reads', (tester) async {
    await pumpExplorer(tester);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await tester.pump();

    expect(find.textContaining('87 %'), findsWidgets);
    await finish(tester);
  });

  testWidgets('shows an ATT error from the device', (tester) async {
    await pumpExplorer(tester);
    bluetooth.failNext(GattError.insufficientAuthentication);

    await tester.tap(find.byIcon(Icons.file_download_outlined));
    await tester.pump();

    expect(find.textContaining('Insufficient authentication'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('discovers again when the device changes its services', (
    tester,
  ) async {
    await pumpExplorer(tester);

    await sensor.addService(
      LocalService(BluetoothUuid.short(0x180a), [
        LocalCharacteristic(
          BluetoothUuid.short(0x2a29),
          properties: const CharacteristicProperties.of(read: true),
          value: 'bt_kit'.codeUnits,
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Device Information'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('says why the link dropped', (tester) async {
    await pumpExplorer(tester);

    sensor.disconnect();
    await tester.pump();
    await tester.pump();

    expect(find.text('Disconnected by the device'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    await finish(tester);
  });
}
