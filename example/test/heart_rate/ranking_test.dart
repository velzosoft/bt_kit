import 'package:bt_radar/features/heart_rate/ranking.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Player = ({String name, int? bpm});

List<String> _rank(List<_Player> players) =>
    rankByBpm(players, (p) => p.bpm).map((p) => p.name).toList();

void main() {
  group('rankByBpm', () {
    test('puts the highest heart rate first', () {
      expect(
        _rank([
          (name: 'Ana', bpm: 72),
          (name: 'Ben', bpm: 140),
          (name: 'Cy', bpm: 95),
        ]),
        ['Ben', 'Cy', 'Ana'],
      );
    });

    test('puts players without a reading last', () {
      expect(
        _rank([
          (name: 'Ana', bpm: null),
          (name: 'Ben', bpm: 60),
          (name: 'Cy', bpm: null),
          (name: 'Di', bpm: 61),
        ]),
        ['Di', 'Ben', 'Ana', 'Cy'],
      );
    });

    test('keeps join order for ties', () {
      expect(
        _rank([
          (name: 'Ana', bpm: 80),
          (name: 'Ben', bpm: 90),
          (name: 'Cy', bpm: 80),
          (name: 'Di', bpm: 90),
        ]),
        ['Ben', 'Di', 'Ana', 'Cy'],
      );
    });

    test('leaves the input untouched', () {
      final players = <_Player>[(name: 'Ana', bpm: 60), (name: 'Ben', bpm: 90)];
      _rank(players);
      expect(players.first.name, 'Ana');
    });

    test('handles an empty showdown', () {
      expect(_rank([]), isEmpty);
    });
  });
}
