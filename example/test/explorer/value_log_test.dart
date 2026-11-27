import 'dart:typed_data';

import 'package:bt_radar/features/explorer/value_log.dart';
import 'package:flutter_test/flutter_test.dart';

TimedValue value(int byte) => TimedValue(Uint8List.fromList([byte]));

void main() {
  test('keeps the newest values first, up to its capacity', () {
    final log = ValueLog(capacity: 3);
    for (var i = 0; i < 5; i++) {
      log.add(value(i));
    }
    expect(log.entries.map((v) => v.bytes.single), [4, 3, 2]);
    expect(log.length, 3);
    expect(log.received, 5);
  });

  test('keeps 50 values by default', () {
    final log = ValueLog();
    for (var i = 0; i < 60; i++) {
      log.add(value(i));
    }
    expect(log.length, 50);
    expect(log.entries.last.bytes.single, 10);
  });

  test('clear empties the log and resets the count', () {
    final log = ValueLog()..add(value(1));
    log.clear();
    expect(log.entries, isEmpty);
    expect(log.received, 0);
  });

  test('clockTime pads every field', () {
    expect(clockTime(DateTime(2026, 11, 25, 9, 3, 7, 42)), '09:03:07.042');
  });
}
