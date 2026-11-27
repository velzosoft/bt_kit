import 'package:bt_radar/features/lab/metrics/sequence_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

SequenceTracker track(List<int> sequence) {
  final tracker = SequenceTracker();
  sequence.forEach(tracker.add);
  return tracker;
}

void main() {
  test('values in order are clean', () {
    final tracker = track([0, 1, 2, 3]);
    expect(tracker.isClean, isTrue);
    expect(tracker.received, 4);
    expect(tracker.highest, 3);
  });

  test('a gap counts as lost values', () {
    final tracker = track([0, 1, 4, 5]);
    expect(tracker.lost, 2);
    expect(tracker.isClean, isFalse);
  });

  test('a missing first value is lost', () {
    expect(track([1, 2]).lost, 1);
  });

  test('a late value is out of order, not lost', () {
    final tracker = track([0, 2, 1, 3]);
    expect(tracker.lost, 0);
    expect(tracker.outOfOrder, 1);
    expect(tracker.duplicates, 0);
  });

  test('a repeated value is a duplicate', () {
    final tracker = track([0, 1, 1, 2]);
    expect(tracker.duplicates, 1);
    expect(tracker.outOfOrder, 0);
    expect(tracker.lost, 0);
  });

  test('an implausible jump is counted, not turned into lost values', () {
    final tracker = track([0, 1, 1 << 30, 2]);
    expect(tracker.implausible, 1);
    expect(tracker.lost, 0);
    expect(tracker.highest, 2);
  });

  test('reports its counts as JSON', () {
    expect(track([0, 2]).toJson(), {
      'received': 2,
      'highestSequence': 2,
      'lost': 1,
      'outOfOrder': 0,
      'duplicates': 0,
      'implausible': 0,
    });
  });
}
