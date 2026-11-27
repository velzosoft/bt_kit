import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../../bluetooth/app_uuids.dart';
import '../../../bluetooth/bluetooth_errors.dart';
import 'party_protocol.dart';

enum SeekerStatus { joining, joined, lost, ended, failed }

/// A seeker's link to the hider's phone: reads the game, follows its
/// state, and sends the time when the target is found.
final class PartySeeker extends ChangeNotifier {
  PartySeeker(this.host, {BtKit? bt}) : _bt = bt ?? BtKit.instance;

  static const _connectTimeout = Duration(seconds: 15);

  /// Room for a finish in one write; iOS negotiates the MTU itself.
  static const _mtu = 185;

  final Peripheral host;
  final BtKit _bt;
  GattCharacteristic? _gameCharacteristic;
  GattCharacteristic? _finishCharacteristic;
  StreamSubscription<Uint8List>? _states;
  StreamSubscription<BluetoothConnectionState>? _link;
  var _status = SeekerStatus.joining;
  String? _message;
  PartyGame? _game;
  int? _missedRound;
  var _leaving = false;
  var _disposed = false;

  SeekerStatus get status => _status;

  /// Why the seeker is not in the party.
  String? get message => _message;

  PartyGame? get game => _game;

  /// The round that was already running on joining, which this seeker sits
  /// out.
  int? get missedRound => _missedRound;

  Future<void> join() async {
    _leaving = false;
    _set(SeekerStatus.joining);
    try {
      await host.connect(timeout: _connectTimeout);
      _link ??= host.connectionStates.listen(_onConnection);
      await _requestMtu();
      await host.discoverServices();
      final game = host.characteristic(AppUuids.party, AppUuids.partyGame);
      final state = host.characteristic(AppUuids.party, AppUuids.partyState);
      final finish = host.characteristic(AppUuids.party, AppUuids.partyFinish);
      if (game == null || state == null || finish == null) {
        throw const FormatException('No party service');
      }
      _gameCharacteristic = game;
      _finishCharacteristic = finish;
      await _states?.cancel();
      _states = state.subscribe().listen(_onState, onError: _onStateError);
      final current = PartyGame.decode(await game.read());
      _missedRound = current.phase == PartyPhase.go ? current.round : null;
      _game = current;
      _set(SeekerStatus.joined);
    } on BluetoothException catch (e) {
      await _fail(describeBluetoothError(e));
    } on FormatException {
      await _fail('That phone is not hosting a party any more.');
    }
  }

  Future<void> finish(PartyFinish finish) async {
    final characteristic = _finishCharacteristic;
    if (characteristic == null) throw const DisconnectedException();
    await characteristic.write(finish.encode());
  }

  Future<void> _requestMtu() async {
    if (!_bt.capabilities.requestMtu) return;
    try {
      await host.requestMtu(_mtu);
    } on BluetoothException catch (_) {}
  }

  void _onState(Uint8List bytes) {
    final state = PartyState.decode(bytes);
    final game = _game;
    if (state == null || game == null) return;
    if (state.phase == PartyPhase.closed) {
      _set(SeekerStatus.ended);
      unawaited(_disconnect());
      return;
    }
    _game = game.withState(state);
    _changed();
    if (state.phase == PartyPhase.finished) unawaited(_readResult());
  }

  void _onStateError(Object error) {
    if (error is DisconnectedException || _status != SeekerStatus.joined) {
      return;
    }
    final message = error is BluetoothException
        ? describeBluetoothError(error)
        : 'The hider’s phone stopped sending updates.';
    unawaited(_fail(message));
  }

  Future<void> _readResult() async {
    try {
      final latest = PartyGame.decode(await _gameCharacteristic!.read());
      if (latest.state != _game?.state) return;
      _game = latest;
      _changed();
    } on BluetoothException catch (_) {
    } on FormatException catch (_) {}
  }

  void _onConnection(BluetoothConnectionState state) {
    if (state != BluetoothConnectionState.disconnected || _leaving) return;
    if (_status == SeekerStatus.joined) {
      _set(
        SeekerStatus.lost,
        'The connection to the hider’s phone dropped. Move closer and '
        'rejoin.',
      );
    }
  }

  Future<void> _fail(String message) async {
    await _disconnect();
    _set(SeekerStatus.failed, message);
  }

  Future<void> _disconnect() async {
    _leaving = true;
    await _states?.cancel();
    _states = null;
    try {
      await host.disconnect();
    } on BluetoothException catch (_) {}
  }

  void _set(SeekerStatus status, [String? message]) {
    _status = status;
    _message = message;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_link?.cancel());
    unawaited(_disconnect());
    super.dispose();
  }
}
