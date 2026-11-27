import 'dart:convert';
import 'dart:typed_data';

import 'short_text.dart';
import 'target_fingerprint.dart';

/// The party service, hosted by the hider's phone:
/// * `partyGame` (read): the [PartyGame] as JSON.
/// * `partyState` (read, notify): the [PartyState] in 2 bytes.
/// * `partyFinish` (write): a seeker's [PartyFinish] as JSON.
enum PartyPhase {
  lobby(0),
  go(1),
  finished(2),
  closed(3);

  const PartyPhase(this.code);

  final int code;

  static PartyPhase? fromCode(int code) {
    for (final phase in values) {
      if (phase.code == code) return phase;
    }
    return null;
  }
}

/// Small enough for one notification at the default MTU.
final class PartyState {
  const PartyState(this.phase, this.round);

  final PartyPhase phase;
  final int round;

  Uint8List encode() => Uint8List.fromList([phase.code, round & 0xff]);

  static PartyState? decode(List<int> bytes) {
    if (bytes.length < 2) return null;
    final phase = PartyPhase.fromCode(bytes[0]);
    return phase == null ? null : PartyState(phase, bytes[1]);
  }

  @override
  bool operator ==(Object other) =>
      other is PartyState && other.phase == phase && other.round == round;

  @override
  int get hashCode => Object.hash(phase, round);
}

final class PartyResult {
  const PartyResult(this.player, this.time);

  final String player;
  final Duration time;
}

/// Everything a seeker needs to know about the game. GATT values hold at
/// most 512 bytes, which the text limits keep it under.
final class PartyGame {
  const PartyGame({
    required this.name,
    required this.target,
    this.phase = PartyPhase.lobby,
    this.round = 0,
    this.winner,
  });

  static const maxNameBytes = 48;

  /// What the hider calls the target, such as "Cookie jar".
  final String name;
  final TargetFingerprint target;
  final PartyPhase phase;
  final int round;
  final PartyResult? winner;

  PartyState get state => PartyState(phase, round);

  static String cleanName(String name) => shortText(name, maxNameBytes);

  PartyGame start() =>
      _copy(phase: PartyPhase.go, round: (round + 1) & 0xff, winner: null);

  PartyGame finish(PartyResult winner) =>
      _copy(phase: PartyPhase.finished, round: round, winner: winner);

  PartyGame reset() =>
      _copy(phase: PartyPhase.lobby, round: round, winner: null);

  PartyGame close() =>
      _copy(phase: PartyPhase.closed, round: round, winner: winner);

  /// The game after a state notification. The winner of a finished round
  /// arrives with the next read.
  PartyGame withState(PartyState state) => _copy(
    phase: state.phase,
    round: state.round,
    winner: state == this.state ? winner : null,
  );

  PartyGame _copy({
    required PartyPhase phase,
    required int round,
    required PartyResult? winner,
  }) => PartyGame(
    name: name,
    target: target,
    phase: phase,
    round: round,
    winner: winner,
  );

  Uint8List encode() => utf8.encode(
    jsonEncode({
      'name': name,
      'phase': phase.code,
      'round': round,
      'target': target.toJson(),
      if (winner case final winner?)
        'winner': {'player': winner.player, 'ms': winner.time.inMilliseconds},
    }),
  );

  /// Throws a [FormatException] if [bytes] are not a party game.
  static PartyGame decode(List<int> bytes) {
    final json = jsonDecode(utf8.decode(bytes));
    if (json case {
      'name': final String name,
      'phase': final int phaseCode,
      'round': final int round,
      'target': final Map<String, Object?> target,
    }) {
      if (PartyPhase.fromCode(phaseCode) case final phase?) {
        return PartyGame(
          name: name,
          target: TargetFingerprint.fromJson(target),
          phase: phase,
          round: round,
          winner: switch (json['winner']) {
            {'player': final String player, 'ms': final int ms} => PartyResult(
              player,
              Duration(milliseconds: ms),
            ),
            _ => null,
          },
        );
      }
    }
    throw const FormatException('Not a party game');
  }
}

/// What a seeker writes when they find the target.
final class PartyFinish {
  const PartyFinish({
    required this.player,
    required this.time,
    required this.round,
  });

  static const maxPlayerBytes = 24;

  final String player;
  final Duration time;
  final int round;

  static String cleanPlayer(String player) => shortText(player, maxPlayerBytes);

  Uint8List encode() => utf8.encode(
    jsonEncode({'player': player, 'ms': time.inMilliseconds, 'round': round}),
  );

  /// Throws a [FormatException] if [bytes] are not a finish.
  static PartyFinish decode(List<int> bytes) {
    if (jsonDecode(utf8.decode(bytes))
        case {
          'player': final String player,
          'ms': final int ms,
          'round': final int round,
        }
        when ms >= 0) {
      return PartyFinish(
        player: cleanPlayer(player),
        time: Duration(milliseconds: ms),
        round: round,
      );
    }
    throw const FormatException('Not a party finish');
  }
}
