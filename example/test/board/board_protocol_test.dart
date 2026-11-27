import 'dart:convert';
import 'dart:ui' show Color;

import 'package:bt_radar/features/board/board_protocol.dart';
import 'package:bt_radar/features/board/hue_ramp.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);

void main() {
  group('ButtonEvent', () {
    test('parses a release with its hold time', () {
      expect(
        ButtonEvent.parse([0x00, 0x03, 0x00, 0x60, 0x09, 0x00, 0x00]),
        ButtonEvent(pressed: false, presses: 3, held: _ms(2400)),
      );
    });

    test('parses a press', () {
      expect(
        ButtonEvent.parse([0x01, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00]),
        const ButtonEvent(pressed: true, presses: 12, held: Duration.zero),
      );
    });

    test('reads little-endian counts and long holds', () {
      final event = ButtonEvent.parse([
        0x00,
        ...[0xff, 0xff],
        ...[0x40, 0x42, 0x0f, 0x00],
      ]);
      expect(event?.presses, 65535);
      expect(event?.held, const Duration(seconds: 1000));
    });

    test('rejects values that are too short', () {
      for (var length = 0; length < ButtonEvent.length; length++) {
        expect(ButtonEvent.parse(List.filled(length, 0)), isNull);
      }
    });

    test('rejects an unknown state', () {
      expect(ButtonEvent.parse([0x02, 0, 0, 0, 0, 0, 0]), isNull);
    });

    test('ignores bytes after the value', () {
      expect(ButtonEvent.parse([0x01, 0x01, 0, 0, 0, 0, 0, 0xaa])?.presses, 1);
    });
  });

  group('LedState', () {
    test('parses a steady green ready state', () {
      expect(
        LedState.parse([0x03, 0x01, 0x00, 0xff, 0x00, 0x00]),
        const LedState(
          state: BoardState.ready,
          pattern: LedPattern.solid,
          color: Color(0xff00ff00),
        ),
      );
    });

    test('parses flashes with their count', () {
      final led = LedState.parse([0x01, 0x05, 0xff, 0x00, 0x00, 0x02]);
      expect(led?.state, BoardState.waiting);
      expect(led?.pattern, LedPattern.flashes);
      expect(led?.color, const Color(0xffff0000));
      expect(led?.flashes, 2);
    });

    test('rejects short values and unknown states or patterns', () {
      expect(LedState.parse([0x03, 0x01, 0x00, 0xff, 0x00]), isNull);
      expect(LedState.parse([0x05, 0x01, 0x00, 0xff, 0x00, 0x00]), isNull);
      expect(LedState.parse([0x03, 0x06, 0x00, 0xff, 0x00, 0x00]), isNull);
    });

    LedState led(LedPattern pattern, {int flashes = 0}) => LedState(
      state: BoardState.waiting,
      pattern: pattern,
      color: const Color(0xff0000ff),
      flashes: flashes,
    );

    List<bool> litAt(LedState state, List<int> milliseconds) => [
      for (final ms in milliseconds) state.colorAt(_ms(ms)) != null,
    ];

    test('blinks slowly: 100 ms on, 900 ms off', () {
      expect(
        litAt(led(LedPattern.slowBlink), [0, 99, 100, 999, 1000, 1099, 1100]),
        [true, true, false, false, true, true, false],
      );
    });

    test('blinks fast: 125 ms on, 125 ms off', () {
      expect(litAt(led(LedPattern.fastBlink), [0, 124, 125, 249, 250]), [
        true,
        true,
        false,
        false,
        true,
      ]);
    });

    test('flashes the given number of times, then goes dark', () {
      expect(
        litAt(led(LedPattern.flashes, flashes: 2), [0, 150, 300, 450, 600]),
        [true, false, true, false, false],
      );
    });

    test('is steady when solid, dark when off', () {
      expect(led(LedPattern.solid).colorAt(_ms(5000)), const Color(0xff0000ff));
      expect(led(LedPattern.off).colorAt(Duration.zero), isNull);
      expect(led(LedPattern.solid).isAnimated, isFalse);
      expect(led(LedPattern.slowBlink).isAnimated, isTrue);
    });

    test('runs the hue ramp from the start of the hold', () {
      final ramp = led(LedPattern.holdRamp);
      expect(ramp.colorAt(_ms(2500)), HueRamp.color(_ms(2500)));
    });
  });

  group('BoardInfo', () {
    test('parses the LED kind and the description', () {
      final info = BoardInfo.parse([
        0x00,
        ...utf8.encode('esp32 rev0.0 esp-idf v6.1.1 fw 1.0.0'),
      ]);
      expect(info?.ledKind, LedKind.singleColor);
      expect(info?.hasColor, isFalse);
      expect(info?.description, 'esp32 rev0.0 esp-idf v6.1.1 fw 1.0.0');
    });

    test('allows an empty description', () {
      final info = BoardInfo.parse([0x02]);
      expect(info?.ledKind, LedKind.addressable);
      expect(info?.hasColor, isTrue);
      expect(info?.description, isEmpty);
    });

    test('rejects an empty value or an unknown LED kind', () {
      expect(BoardInfo.parse([]), isNull);
      expect(BoardInfo.parse([0x03, 0x41]), isNull);
    });
  });

  group('BlinkCommand', () {
    test('encodes three white flashes', () {
      expect(const BlinkCommand(Color(0xffffffff)).encode(), [
        0x01,
        0xff,
        0xff,
        0xff,
        0x03,
      ]);
    });

    test('encodes the color and the count', () {
      expect(const BlinkCommand(Color(0xffff00ff), count: 10).encode(), [
        0x01,
        0xff,
        0x00,
        0xff,
        0x0a,
      ]);
    });

    test('refuses counts the board refuses', () {
      for (final count in [0, 11]) {
        expect(
          () => BlinkCommand(const Color(0xffffffff), count: count).encode(),
          throwsRangeError,
        );
      }
    });

    test('stops with a single zero byte', () {
      expect(BlinkCommand.stop, [0x00]);
    });
  });
}
