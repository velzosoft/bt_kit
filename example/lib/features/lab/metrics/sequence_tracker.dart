/// Checks sequence numbers that should arrive as 0, 1, 2, … with none
/// missing, repeated or out of order.
///
/// A value is lost while it has not arrived after a later one did; if it
/// arrives afterwards it counts as out of order instead.
final class SequenceTracker {
  /// A jump further than this is a corrupt value, not lost ones.
  static const maxGap = 100000;

  final _missing = <int>{};
  var _next = 0;
  var received = 0;
  var outOfOrder = 0;
  var duplicates = 0;
  var implausible = 0;

  int get lost => _missing.length;

  /// The highest sequence number seen, or -1 before the first.
  int get highest => _next - 1;

  bool get isClean =>
      lost == 0 && outOfOrder == 0 && duplicates == 0 && implausible == 0;

  void add(int sequence) {
    received++;
    if (sequence >= _next) {
      if (sequence - _next > maxGap) {
        implausible++;
        return;
      }
      for (var missing = _next; missing < sequence; missing++) {
        _missing.add(missing);
      }
      _next = sequence + 1;
    } else if (_missing.remove(sequence)) {
      outOfOrder++;
    } else {
      duplicates++;
    }
  }

  Map<String, Object?> toJson() => {
    'received': received,
    'highestSequence': highest,
    'lost': lost,
    'outOfOrder': outOfOrder,
    'duplicates': duplicates,
    'implausible': implausible,
  };
}
