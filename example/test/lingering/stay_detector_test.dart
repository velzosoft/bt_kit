import 'package:bt_radar/features/lingering/stay_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// [count] devices that belong to one place, such as `cafe0`..`cafe9`.
Set<String> place(String name, int count) => {
  for (var i = 0; i < count; i++) '$name$i',
};

void main() {
  final start = DateTime(2026, 11, 25, 9);
  DateTime minutes(int m) => start.add(Duration(minutes: m));
  const tracker = 'tracker';

  late StayDetector detector;
  setUp(() => detector = StayDetector());

  /// Takes the tracker through new places, one snapshot each.
  void travel(List<(int, String)> stops) {
    for (final (minute, name) in stops) {
      detector.addSnapshot(minutes(minute), {tracker, ...place(name, 10)});
    }
  }

  test('a place that does not change never churns', () {
    for (var m = 0; m < 60; m++) {
      expect(
        detector.addSnapshot(minutes(m), {tracker, ...place('home', 10)}),
        isFalse,
      );
    }
    expect(detector.churnEvents, 0);
    expect(detector.staysOf(tracker), 0);
  });

  test('replacing 80% of the others is a change; who stayed is counted', () {
    detector.addSnapshot(minutes(0), {tracker, ...place('a', 10)});
    final changed = detector.addSnapshot(minutes(1), {
      tracker,
      'a0',
      'a1',
      ...place('b', 10),
    });
    expect(changed, isTrue);
    expect(detector.churnEvents, 1);
    expect(detector.staysOf(tracker), 1);
    expect(detector.staysOf('a0'), 1);
    expect(detector.staysOf('b0'), 0);
  });

  test('replacing less than 80% is not a change', () {
    detector.addSnapshot(minutes(0), {tracker, ...place('a', 10)});
    final changed = detector.addSnapshot(minutes(1), {
      tracker,
      'a0',
      'a1',
      'a2',
      ...place('b', 10),
    });
    expect(changed, isFalse);
    expect(detector.churnEvents, 0);
  });

  test('a change is measured against the last reference, not the last '
      'snapshot', () {
    detector.addSnapshot(minutes(0), {tracker, ...place('a', 10)});
    detector.addSnapshot(minutes(1), {
      tracker,
      ...place('a', 5),
      ...place('b', 5),
    });
    expect(detector.churnEvents, 0);
    detector.addSnapshot(minutes(2), {
      tracker,
      ...place('a', 2),
      ...place('b', 5),
      ...place('c', 3),
    });
    expect(detector.churnEvents, 1);
  });

  test('flags a device that stays through 3 changes within an hour', () {
    travel([(0, 'home'), (10, 'street'), (20, 'bus'), (30, 'office')]);
    expect(detector.churnEvents, 3);
    final flagged = detector.flagged;
    expect(flagged.map((d) => d.id), [tracker]);
    expect(flagged.single.stays, 3);
    expect(flagged.single.firstSeen, minutes(0));
    expect(flagged.single.flaggedAt, minutes(30));
  });

  test('does not flag 3 changes spread over more than an hour', () {
    travel([(0, 'home'), (10, 'street'), (40, 'bus'), (75, 'office')]);
    expect(detector.churnEvents, 3);
    expect(detector.flagged, isEmpty);
    expect(detector.unflaggedStayers, 1);
  });

  test('stays flagged, and keeps counting', () {
    travel([
      (0, 'home'),
      (10, 'street'),
      (20, 'bus'),
      (30, 'office'),
      (150, 'gym'),
    ]);
    expect(detector.flagged.single.stays, 4);
    expect(detector.flagged.single.flaggedAt, minutes(30));
  });

  test('a device missing at a change does not count for it', () {
    detector.addSnapshot(minutes(0), {tracker, ...place('a', 10)});
    detector.addSnapshot(minutes(10), place('b', 10));
    expect(detector.churnEvents, 1);
    expect(detector.staysOf(tracker), 0);
  });

  test('too few devices to judge: the reference moves on', () {
    detector.addSnapshot(minutes(0), {tracker, ...place('home', 3)});
    expect(
      detector.addSnapshot(minutes(1), {tracker, ...place('street', 20)}),
      isFalse,
    );
    expect(detector.churnEvents, 0);
    expect(
      detector.addSnapshot(minutes(2), {tracker, ...place('bus', 20)}),
      isTrue,
    );
    expect(detector.staysOf(tracker), 1);
  });

  test('empty snapshots are ignored', () {
    detector.addSnapshot(minutes(0), {tracker, ...place('a', 10)});
    expect(detector.addSnapshot(minutes(1), {}), isFalse);
    expect(detector.churnEvents, 0);
  });

  test('a change with no one staying still counts as a change', () {
    detector.addSnapshot(minutes(0), place('a', 10));
    expect(detector.addSnapshot(minutes(1), place('b', 10)), isTrue);
    expect(detector.churnEvents, 1);
    expect(detector.flagged, isEmpty);
    expect(detector.unflaggedStayers, 0);
  });

  test('flagged devices are sorted by stays', () {
    const watch = 'watch';
    detector.addSnapshot(minutes(0), {tracker, ...place('a', 10)});
    for (final (m, name) in [
      (5, 'b'),
      (10, 'c'),
      (15, 'd'),
      (20, 'e'),
      (25, 'f'),
    ]) {
      detector.addSnapshot(minutes(m), {
        tracker,
        if (m >= 10) watch,
        ...place(name, 10),
      });
    }
    expect(detector.flagged.map((d) => d.id), [tracker, watch]);
    expect(detector.flagged.map((d) => d.stays), [5, 3]);
  });
}
