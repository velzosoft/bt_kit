import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'hue_ramp.dart';

/// Where the board's link is, as its LED shows it.
enum BoardState { starting, waiting, connected, ready, error }

/// What the board's LED draws.
enum LedPattern { off, solid, slowBlink, fastBlink, holdRamp, flashes }

enum LedKind { singleColor, rgb, addressable }

/// The LED pattern timings, which the on-screen LED copies.
abstract final class LedTiming {
  static const slowBlinkOn = Duration(milliseconds: 100);
  static const slowBlinkPeriod = Duration(milliseconds: 1000);
  static const fastBlinkOn = Duration(milliseconds: 125);
  static const fastBlinkPeriod = Duration(milliseconds: 250);
  static const flashOn = Duration(milliseconds: 150);
  static const flashPeriod = Duration(milliseconds: 300);
}

/// A press or a release of the board's button.
final class ButtonEvent {
  const ButtonEvent({
    required this.pressed,
    required this.presses,
    required this.held,
  });

  static const length = 7;

  final bool pressed;

  /// Presses since the board started; it wraps at 65536.
  final int presses;

  /// The whole hold in a release, the hold so far when read during one, and
  /// zero in a press.
  final Duration held;

  /// Returns null for a value that is too short or has an unknown state.
  static ButtonEvent? parse(List<int> value) {
    if (value.length < length || value[0] > 1) return null;
    final data = ByteData.sublistView(Uint8List.fromList(value));
    return ButtonEvent(
      pressed: value[0] == 1,
      presses: data.getUint16(1, Endian.little),
      held: Duration(milliseconds: data.getUint32(3, Endian.little)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ButtonEvent &&
      other.pressed == pressed &&
      other.presses == presses &&
      other.held == held;

  @override
  int get hashCode => Object.hash(pressed, presses, held);

  @override
  String toString() =>
      'ButtonEvent(${pressed ? 'pressed' : 'released'}, $presses, $held)';
}

/// What the board's LED shows, as the board reports it.
final class LedState {
  const LedState({
    required this.state,
    required this.pattern,
    required this.color,
    this.flashes = 0,
  });

  static const length = 6;

  final BoardState state;
  final LedPattern pattern;

  /// The color at full brightness. For the hold ramp, the color the hold
  /// started with.
  final Color color;

  /// How many flashes, for [LedPattern.flashes].
  final int flashes;

  /// Returns null for a value that is too short or has an unknown state or
  /// pattern.
  static LedState? parse(List<int> value) {
    if (value.length < length ||
        value[0] >= BoardState.values.length ||
        value[1] >= LedPattern.values.length) {
      return null;
    }
    return LedState(
      state: BoardState.values[value[0]],
      pattern: LedPattern.values[value[1]],
      color: Color.fromARGB(0xff, value[2], value[3], value[4]),
      flashes: value[5],
    );
  }

  /// Whether the LED changes while this state lasts.
  bool get isAnimated =>
      pattern != LedPattern.off && pattern != LedPattern.solid;

  /// The LED's color [elapsed] after this state began, or null while it is
  /// dark.
  Color? colorAt(Duration elapsed) => switch (pattern) {
    LedPattern.off => null,
    LedPattern.solid => color,
    LedPattern.slowBlink => _blink(
      elapsed,
      LedTiming.slowBlinkOn,
      LedTiming.slowBlinkPeriod,
    ),
    LedPattern.fastBlink => _blink(
      elapsed,
      LedTiming.fastBlinkOn,
      LedTiming.fastBlinkPeriod,
    ),
    LedPattern.flashes =>
      elapsed < LedTiming.flashPeriod * flashes
          ? _blink(elapsed, LedTiming.flashOn, LedTiming.flashPeriod)
          : null,
    LedPattern.holdRamp => HueRamp.color(elapsed),
  };

  Color? _blink(Duration elapsed, Duration on, Duration period) =>
      elapsed.inMicroseconds % period.inMicroseconds < on.inMicroseconds
      ? color
      : null;

  @override
  bool operator ==(Object other) =>
      other is LedState &&
      other.state == state &&
      other.pattern == pattern &&
      other.color == color &&
      other.flashes == flashes;

  @override
  int get hashCode => Object.hash(state, pattern, color, flashes);

  @override
  String toString() => 'LedState(${state.name}, ${pattern.name}, $flashes)';
}

/// The board's hardware and firmware.
final class BoardInfo {
  const BoardInfo({required this.ledKind, required this.description});

  final LedKind ledKind;

  /// Such as `esp32 rev0.0 esp-idf v6.1.1 fw 1.0.0`.
  final String description;

  bool get hasColor => ledKind != LedKind.singleColor;

  /// Returns null for an empty value or an unknown LED kind.
  static BoardInfo? parse(List<int> value) {
    if (value.isEmpty || value[0] >= LedKind.values.length) return null;
    return BoardInfo(
      ledKind: LedKind.values[value[0]],
      description: utf8.decode(value.sublist(1), allowMalformed: true),
    );
  }
}

/// Flashes the board's LED [count] times in [color].
final class BlinkCommand {
  const BlinkCommand(this.color, {this.count = 3});

  static const maxCount = 10;

  /// Stops flashing; the LED goes back to its state pattern.
  static const stop = [0x00];

  final Color color;
  final int count;

  Uint8List encode() {
    RangeError.checkValueInInterval(count, 1, maxCount, 'count');
    final argb = color.toARGB32();
    return Uint8List.fromList([
      0x01,
      argb >> 16 & 0xff,
      argb >> 8 & 0xff,
      argb & 0xff,
      count,
    ]);
  }
}
