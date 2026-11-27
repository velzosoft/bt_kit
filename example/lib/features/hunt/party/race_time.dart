/// The 3-2-1 before every round.
abstract final class Countdown {
  static const length = Duration(seconds: 3);
  static const _goShownFor = Duration(milliseconds: 800);

  /// "3", "2", "1", then "Go!", then null once it is over.
  static String? labelAt(Duration elapsed) {
    if (elapsed.isNegative) return '${length.inSeconds}';
    if (elapsed < length) return '${length.inSeconds - elapsed.inSeconds}';
    if (elapsed < length + _goShownFor) return 'Go!';
    return null;
  }
}

/// Such as "12.3 s" or "1:05.0".
String formatRaceTime(Duration time) {
  final tenths = time.isNegative ? 0 : time.inMilliseconds ~/ 100;
  final seconds = tenths ~/ 10;
  final fraction = tenths % 10;
  if (seconds < 60) return '$seconds.$fraction s';
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest.$fraction';
}
