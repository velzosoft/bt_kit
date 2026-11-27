/// Decides when a seeker has found the target: a very strong signal held
/// for [hold], so that a passing spike does not count.
final class FoundDetector {
  FoundDetector({
    this.threshold = 0.9,
    this.hold = const Duration(milliseconds: 1500),
  });

  /// Strong enough for the seeker to claim the find by hand.
  static const nearEnough = 0.7;

  final double threshold;
  final Duration hold;
  DateTime? _strongSince;

  /// Takes the current strength, or null while the target is not heard,
  /// and returns whether it has been found.
  bool update(double? strength, DateTime now) {
    if (strength == null || strength < threshold) {
      _strongSince = null;
      return false;
    }
    final since = _strongSince ??= now;
    return now.difference(since) >= hold;
  }

  void reset() => _strongSince = null;
}
