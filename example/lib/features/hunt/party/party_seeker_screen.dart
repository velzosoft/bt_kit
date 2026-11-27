import 'dart:io';

import 'package:bt_kit/bt_kit.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/app_scope.dart';
import '../../../app/bluetooth_state_panel.dart';
import '../../../bluetooth/scanner.dart';
import '../../../widgets/code_sheet.dart';
import '../clicker.dart';
import '../feedback_toggles.dart';
import '../message_panel.dart';
import 'party_code.dart';
import 'party_protocol.dart';
import 'party_seeker.dart';
import 'party_seeker_views.dart';
import 'seeker_race.dart';
import 'target_matcher.dart';
import 'target_picker.dart';

/// A seeker's phone in a party: waits for the start, then races to the
/// target.
class PartySeekerScreen extends StatefulWidget {
  const PartySeekerScreen({super.key, required this.host});

  final Peripheral host;

  @override
  State<PartySeekerScreen> createState() => _PartySeekerScreenState();
}

class _PartySeekerScreenState extends State<PartySeekerScreen> {
  late final _seeker = PartySeeker(widget.host);
  late final Scanner _scanner = AppScope.of(context).scanner;
  final _clicker = Clicker();
  final _player = TextEditingController();
  SeekerRace? _race;
  String? _pickedId;

  @override
  void initState() {
    super.initState();
    _seeker.addListener(_onSeeker);
    _scanner.addListener(_onScanner);
    _seeker.join();
  }

  @override
  void dispose() {
    _scanner.removeListener(_onScanner);
    _seeker
      ..removeListener(_onSeeker)
      ..dispose();
    _race?.dispose();
    _clicker.dispose();
    _player.dispose();
    super.dispose();
  }

  String get _playerName {
    final name = PartyFinish.cleanPlayer(_player.text);
    return name.isEmpty ? 'A seeker' : name;
  }

  TargetChoice _choice(PartyGame game) {
    final nearby = [
      for (final device in _scanner.bySignal)
        if (device.id != widget.host.id) device,
    ];
    final matches = TargetMatch.rank([
      for (final device in nearby)
        TargetMatch(
          device,
          TargetMatcher.confidence(
            game.target,
            id: device.id,
            data: device.data,
            idsAreAddresses: Platform.isAndroid,
          ),
          device.rssi,
        ),
    ]);
    final selectedId =
        _race?.targetId ?? _pickedId ?? matches.firstOrNull?.device.id;
    return TargetChoice(
      matches: matches,
      nearby: nearby,
      selected: selectedId == null ? null : _scanner[selectedId],
    );
  }

  String? _bestTarget(PartyGame game) =>
      _pickedId ?? _choice(game).matches.firstOrNull?.device.id;

  void _onSeeker() {
    final game = _seeker.game;
    final race = _race;
    if (_seeker.status != SeekerStatus.joined || game == null) {
      race?.end();
      return;
    }
    final round = game.round;
    final isNewRound =
        game.phase == PartyPhase.go &&
        race?.round != round &&
        round != _seeker.missedRound;
    if (isNewRound) {
      race?.dispose();
      final next = SeekerRace(
        round: round,
        scanner: _scanner,
        clicker: _clicker,
        send: (time) => _seeker.finish(
          PartyFinish(player: _playerName, time: time, round: round),
        ),
      )..targetId = _bestTarget(game);
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _race = next);
    } else if (game.phase != PartyPhase.go && race?.round == round) {
      race?.end();
    }
  }

  void _onScanner() {
    final race = _race;
    final game = _seeker.game;
    if (race == null || game == null || race.targetId != null) return;
    if (race.stage case RaceStage.countdown || RaceStage.hunting) {
      race.targetId = _bestTarget(game);
    }
  }

  void _pick(String id) {
    setState(() => _pickedId = id);
    _race?.targetId = id;
  }

  void _leave() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Party'),
      actions: [FeedbackToggles(_clicker), const CodeButton(partyCode)],
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([_seeker, _scanner, ?_race]),
      builder: (context, _) => BluetoothStatePanel.needed(_scanner.status)
          ? BluetoothStatePanel(scanner: _scanner)
          : _body(),
    ),
  );

  Widget _body() => switch (_seeker.status) {
    SeekerStatus.joining => const MessagePanel.busy('Joining the party…'),
    SeekerStatus.failed => MessagePanel(
      icon: Icons.error_outline,
      title: 'Could not join',
      body: _seeker.message ?? '',
      primary: ('Try again', _seeker.join),
      secondary: ('Back', _leave),
    ),
    SeekerStatus.lost => MessagePanel(
      icon: Icons.link_off,
      title: 'Lost the hider',
      body: _seeker.message ?? '',
      primary: ('Rejoin', _seeker.join),
      secondary: ('Back', _leave),
    ),
    SeekerStatus.ended => MessagePanel(
      icon: Icons.celebration_outlined,
      title: 'The party is over',
      body: 'The hider ended the party. Thanks for playing!',
      primary: ('Back', _leave),
    ),
    SeekerStatus.joined => _joined(_seeker.game!),
  };

  Widget _joined(PartyGame game) {
    final race = _race;
    final choice = _choice(game);
    SeekerLobbyView lobby(String waiting) => SeekerLobbyView(
      game: game,
      choice: choice,
      onPick: _pick,
      player: _player,
      waiting: waiting,
    );
    return switch (game.phase) {
      PartyPhase.go when race != null && race.round == game.round =>
        SeekerRaceView(race: race, game: game, choice: choice, onPick: _pick),
      PartyPhase.go => lobby(
        'A round is under way. You will join the next one.',
      ),
      PartyPhase.finished => SeekerResultView(
        game: game,
        race: race?.round == game.round ? race : null,
        player: _playerName,
      ),
      PartyPhase.lobby ||
      PartyPhase.closed => lobby('Waiting for the hider to start…'),
    };
  }
}
