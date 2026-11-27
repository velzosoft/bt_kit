import 'dart:collection';
import 'dart:typed_data';

/// A value an attribute returned or pushed, and when it arrived.
final class TimedValue {
  TimedValue(this.bytes, [DateTime? at]) : at = at ?? DateTime.now();

  final Uint8List bytes;
  final DateTime at;
}

/// The most recent values a characteristic pushed, newest first.
final class ValueLog {
  ValueLog({this.capacity = 50});

  final int capacity;
  final _entries = ListQueue<TimedValue>();
  var _received = 0;

  Iterable<TimedValue> get entries => _entries;

  int get length => _entries.length;

  /// Every value added since the last [clear], including dropped ones.
  int get received => _received;

  void add(TimedValue value) {
    _entries.addFirst(value);
    if (_entries.length > capacity) _entries.removeLast();
    _received++;
  }

  void clear() {
    _entries.clear();
    _received = 0;
  }
}

/// Such as `14:03:07.042`.
String clockTime(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  final millis = time.millisecond.toString().padLeft(3, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
}
