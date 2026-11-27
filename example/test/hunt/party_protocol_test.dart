import 'dart:convert';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/hunt/party/party_protocol.dart';
import 'package:bt_radar/features/hunt/party/short_text.dart';
import 'package:bt_radar/features/hunt/party/target_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const target = TargetFingerprint(localName: 'Buds', company: 0x0075);
  const game = PartyGame(name: 'Cookie jar', target: target);

  group('PartyState', () {
    test('fits in 2 bytes and survives a round trip', () {
      const state = PartyState(PartyPhase.go, 3);
      expect(state.encode(), [1, 3]);
      expect(PartyState.decode(state.encode()), state);
    });

    test('rejects short values and unknown phases', () {
      expect(PartyState.decode([1]), isNull);
      expect(PartyState.decode([9, 1]), isNull);
    });
  });

  group('PartyGame', () {
    test('survives a round trip with a winner', () {
      final finished = game.start().finish(
        const PartyResult('Sam', Duration(milliseconds: 12345)),
      );
      final decoded = PartyGame.decode(finished.encode());
      expect(decoded.name, 'Cookie jar');
      expect(decoded.phase, PartyPhase.finished);
      expect(decoded.round, 1);
      expect(decoded.winner?.player, 'Sam');
      expect(decoded.winner?.time, const Duration(milliseconds: 12345));
      expect(decoded.target.localName, 'Buds');
      expect(decoded.target.company, 0x0075);
    });

    test('starting a round clears the winner and counts up', () {
      final next = game
          .start()
          .finish(const PartyResult('Sam', Duration.zero))
          .start();
      expect(next.phase, PartyPhase.go);
      expect(next.round, 2);
      expect(next.winner, isNull);
    });

    test('the round wraps at 255 like the state byte', () {
      final last = PartyGame(name: 'x', target: target, round: 255);
      expect(last.start().round, 0);
    });

    test('a state notification keeps the winner only for the same round', () {
      final finished = game.start().finish(
        const PartyResult('Sam', Duration.zero),
      );
      expect(finished.withState(finished.state).winner, isNotNull);
      expect(
        finished.withState(const PartyState(PartyPhase.go, 2)).winner,
        isNull,
      );
    });

    test('rejects anything that is not a game', () {
      for (final bytes in [
        utf8.encode('not json'),
        utf8.encode('{"name": "x"}'),
        utf8.encode('{"name":"x","phase":7,"round":0,"target":{}}'),
        [0xff, 0xfe],
      ]) {
        expect(() => PartyGame.decode(bytes), throwsFormatException);
      }
    });

    test('the largest game still fits a 512-byte GATT value', () {
      final quotes = '"' * 100;
      final largest =
          PartyGame(
            name: PartyGame.cleanName(quotes),
            round: 255,
            target: TargetFingerprint(
              address: 'AA:BB:CC:DD:EE:FF',
              localName: shortText(quotes, TargetFingerprint.maxNameBytes),
              beaconCode: 'ABCD',
              company: 0xffff,
              services: [
                for (var i = 0; i < TargetFingerprint.maxServices; i++)
                  BluetoothUuid.parse('0000000$i-1111-2222-3333-444444444444'),
              ],
            ),
          ).start().finish(
            PartyResult(
              PartyFinish.cleanPlayer(quotes),
              const Duration(hours: 99),
            ),
          );
      expect(largest.encode().length, lessThanOrEqualTo(512));
    });
  });

  group('PartyFinish', () {
    test('survives a round trip', () {
      const finish = PartyFinish(
        player: 'Sam',
        time: Duration(milliseconds: 9876),
        round: 4,
      );
      final decoded = PartyFinish.decode(finish.encode());
      expect(decoded.player, 'Sam');
      expect(decoded.time, const Duration(milliseconds: 9876));
      expect(decoded.round, 4);
    });

    test('rejects negative times and other shapes', () {
      expect(
        () => PartyFinish.decode(
          utf8.encode('{"player":"Sam","ms":-1,"round":1}'),
        ),
        throwsFormatException,
      );
      expect(
        () => PartyFinish.decode(utf8.encode('[]')),
        throwsFormatException,
      );
    });
  });

  group('shortText', () {
    test('trims and drops control characters', () {
      expect(shortText('  Cookie\n jar \t', 48), 'Cookie jar');
    });

    test('cuts on a character boundary by UTF-8 length', () {
      expect(shortText('ééé', 5), 'éé');
      expect(utf8.encode(shortText('🍪🍪🍪', 9)).length, 8);
    });
  });
}
