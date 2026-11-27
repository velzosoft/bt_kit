import 'package:flutter/widgets.dart';

/// One color per player. No greens, so every color survives the chroma key
/// in streamer mode.
abstract final class PlayerPalette {
  static const colors = [
    Color(0xffff5a5f),
    Color(0xff4aa8ff),
    Color(0xfff5e14b),
    Color(0xffb47cff),
    Color(0xffffa53d),
    Color(0xffff6fb5),
  ];

  /// The first color nobody uses yet.
  static Color next(Iterable<Color> taken) {
    final used = taken.toSet();
    return colors.firstWhere(
      (c) => !used.contains(c),
      orElse: () => colors.first,
    );
  }
}
