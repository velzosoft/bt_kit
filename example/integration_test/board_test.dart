import 'dart:async';
import 'dart:ui' show Color;

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/app_uuids.dart';
import 'package:bt_radar/bluetooth/scanner.dart';
import 'package:bt_radar/features/board/board_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/bluetooth_setup.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Peripheral? board;

  GattCharacteristic characteristic(BluetoothUuid uuid) =>
      board!.characteristic(AppUuids.board, uuid)!;

  setUpAll(() async {
    await prepareBluetooth();
    board = await _findBoard();
    if (board == null) {
      debugPrint(
        'No Hello board advertised within 20 s. Flash an ESP32 with '
        'example/peripheral/esp32_board/ and power it nearby.',
      );
      return;
    }
    await board!.connect();
    await board!.discoverServices();
  });

  tearDownAll(() async => board?.disconnect());

  void boardTest(String description, Future<void> Function() body) =>
      test(description, () async {
        if (board == null) {
          markTestSkipped('No Hello board nearby');
          return;
        }
        await body();
      }, timeout: const Timeout(Duration(seconds: 30)));

  boardTest('serves the profile', () async {
    final info = BoardInfo.parse(
      await characteristic(AppUuids.boardInfo).read(),
    );
    debugPrint('Board info: ${info?.ledKind.name} ${info?.description}');
    expect(info, isNotNull);
    expect(info!.description, startsWith('esp32'));

    final button = ButtonEvent.parse(
      await characteristic(AppUuids.boardButton).read(),
    );
    expect(button, isNotNull);

    final led = LedState.parse(await characteristic(AppUuids.boardLed).read());
    expect(led?.state, BoardState.connected);
  });

  boardTest('turns ready while the button is subscribed', () async {
    final leds = _LedReports(characteristic(AppUuids.boardLed));
    await leds.started;

    final button = characteristic(AppUuids.boardButton)
        .subscribe()
        .listen((_) {});
    final ready = await leds.next();
    expect(ready.state, BoardState.ready);
    expect(ready.pattern, LedPattern.solid);
    expect(ready.color, const Color(0xff00ff00));

    await button.cancel();
    final connected = await leds.next();
    expect(connected.state, BoardState.connected);
    expect(connected.pattern, LedPattern.fastBlink);
    await leds.close();
  });

  boardTest('flashes, restarts a flash and stops on command', () async {
    final command = characteristic(AppUuids.boardLedCommand);
    final leds = _LedReports(characteristic(AppUuids.boardLed));
    await leds.started;

    await command.write(const BlinkCommand(Color(0xffff00ff)).encode());
    final flashing = await leds.next();
    expect(flashing.pattern, LedPattern.flashes);
    expect(flashing.color, const Color(0xffff00ff));
    expect(flashing.flashes, 3);

    await command.write(const BlinkCommand(Color(0xffff00ff)).encode());
    expect(await leds.next(), flashing);

    await command.write(BlinkCommand.stop);
    expect((await leds.next()).pattern, LedPattern.fastBlink);

    await command.write(
      const BlinkCommand(Color(0xffffffff), count: 1).encode(),
    );
    expect((await leds.next()).pattern, LedPattern.flashes);
    final after = await leds.next(timeout: const Duration(seconds: 1));
    expect(after.pattern, LedPattern.fastBlink);
    await leds.close();
  });

  boardTest('refuses invalid LED commands with the ATT errors', () async {
    final command = characteristic(AppUuids.boardLedCommand);
    const length = GattError.invalidAttributeValueLength;
    const notAllowed = GattError.valueNotAllowed;
    final cases = <(List<int>, GattError)>[
      ([], length),
      ([0x00, 0x00], length),
      ([0x01, 0xff, 0xff, 0xff], length),
      ([0x01, 0xff, 0xff, 0xff, 0x03, 0x00], length),
      ([0x02], notAllowed),
      ([0xff, 0x00, 0x00], notAllowed),
      ([0x01, 0xff, 0xff, 0xff, 0x00], notAllowed),
      ([0x01, 0xff, 0xff, 0xff, 0x0b], notAllowed),
    ];
    for (final (value, error) in cases) {
      await expectLater(
        command.write(value),
        throwsA(isA<GattException>().having((e) => e.error, 'error', error)),
        reason: 'writing $value',
      );
    }
    await command.write(
      const BlinkCommand(Color(0xff00ff00), count: 10).encode(),
    );
    await command.write(BlinkCommand.stop);
  });

  boardTest('reads a fresh signal strength', () async {
    final rssi = await board!.readRssi();
    expect(rssi, inInclusiveRange(-110, -10));
  });
}

Future<Peripheral?> _findBoard() async {
  try {
    final ad = await BtKit.instance
        .scan(Scanner.options)
        .firstWhere((ad) => ad.data.serviceUuids.contains(AppUuids.board))
        .timeout(const Duration(seconds: 20));
    debugPrint('Found ${ad.data.localName} (${ad.peripheral.id})');
    return ad.peripheral;
  } on TimeoutException {
    return null;
  }
}

/// The LED values a board notifies, one at a time.
final class _LedReports {
  _LedReports(GattCharacteristic led) {
    _subscription = led.subscribe().listen((value) {
      final state = LedState.parse(value);
      if (state != null) _reports.add(state);
    });
    started = _waitForSubscription(led);
  }

  final _reports = StreamController<LedState>();
  late final StreamIterator<LedState> _queue = StreamIterator(_reports.stream);
  late final StreamSubscription<Uint8List> _subscription;
  late final Future<void> started;

  static Future<void> _waitForSubscription(GattCharacteristic led) async {
    for (var i = 0; i < 50 && !led.isNotifying; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(led.isNotifying, isTrue, reason: 'LED notifications turn on');
  }

  Future<LedState> next({Duration timeout = const Duration(seconds: 3)}) async {
    final more = await _queue.moveNext().timeout(timeout);
    if (!more) throw StateError('The LED subscription ended');
    return _queue.current;
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _queue.cancel();
    await _reports.close();
  }
}
