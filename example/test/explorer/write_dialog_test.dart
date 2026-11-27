import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/explorer/write_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

int limit({required bool withResponse}) => withResponse ? 512 : 4;

Future<void> open(
  WidgetTester tester,
  CharacteristicProperties properties, {
  void Function(WriteDialogResult?)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await showWriteDialog(
              context,
              name: 'LED',
              properties: properties,
              limit: limit,
            );
            onResult?.call(result);
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

FilledButton writeButton(WidgetTester tester) =>
    tester.widget(find.widgetWithText(FilledButton, 'Write'));

void main() {
  const both = CharacteristicProperties.of(
    write: true,
    writeWithoutResponse: true,
  );

  testWidgets('writes hex with the chosen write type', (tester) async {
    WriteDialogResult? result;
    await open(tester, both, onResult: (r) => result = r);

    await tester.enterText(find.byType(TextField), '01 ff');
    await tester.pump();
    expect(find.text('2 of 512 bytes'), findsOneWidget);

    await tester.tap(find.text('Without'));
    await tester.pump();
    expect(find.text('2 of 4 bytes'), findsOneWidget);

    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();
    expect(result?.bytes, [0x01, 0xff]);
    expect(result?.withResponse, isFalse);
  });

  testWidgets('blocks values over the limit', (tester) async {
    await open(
      tester,
      const CharacteristicProperties.of(writeWithoutResponse: true),
    );
    expect(find.text('Written without response'), findsOneWidget);

    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.text('5 bytes is over the limit of 4'), findsOneWidget);
    expect(writeButton(tester).onPressed, isNull);
  });

  testWidgets('switching format converts the input', (tester) async {
    await open(tester, both);
    await tester.enterText(find.byType(TextField), '48 69');
    await tester.tap(find.text('Text'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Hi'), findsOneWidget);
  });
}
