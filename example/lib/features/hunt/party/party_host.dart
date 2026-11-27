import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../../bluetooth/app_uuids.dart';
import '../../../bluetooth/bluetooth_errors.dart';
import 'party_protocol.dart';
import 'target_fingerprint.dart';

enum HostStatus { opening, open, needsPermission, unsupported, failed }

/// The hider's side of a party: a GATT server that serves the game,
/// notifies every phase change and takes the seekers' finishes, and an
/// advertisement so that seekers can find it.
final class PartyHost extends ChangeNotifier {
  PartyHost({
    required String name,
    required TargetFingerprint target,
    BtKit? bt,
  }) : _bt = bt ?? BtKit.instance,
       _game = PartyGame(name: name, target: target);

  static const _goodbyeTimeout = Duration(seconds: 1);

  final BtKit _bt;
  PartyGame _game;
  late final _gameCharacteristic = LocalCharacteristic(
    AppUuids.partyGame,
    properties: const CharacteristicProperties.of(read: true),
    onRead: (_) => _game.encode(),
  );
  late final _stateCharacteristic = LocalCharacteristic(
    AppUuids.partyState,
    properties: const CharacteristicProperties.of(read: true, notify: true),
    onRead: (_) => _game.state.encode(),
  );
  late final _finishCharacteristic = LocalCharacteristic(
    AppUuids.partyFinish,
    properties: const CharacteristicProperties.of(write: true),
    onWrite: _onFinish,
  );
  GattServer? _server;
  AdvertisingSession? _advertising;
  StreamSubscription<SubscriptionChange>? _subscriptions;
  var _status = HostStatus.opening;
  String? _message;
  DateTime? _goAt;
  var _disposed = false;

  HostStatus get status => _status;

  /// Why the party is not open.
  String? get message => _message;

  PartyGame get game => _game;

  /// When the current round's countdown started.
  DateTime? get goAt => _goAt;

  /// Seekers listening for the start. iOS reports a seeker only once it
  /// subscribes, so this counts subscribers on both platforms.
  int get seekers => _server?.subscribers(_stateCharacteristic).length ?? 0;

  Future<void> open() async {
    if (_server != null) return;
    _set(HostStatus.opening);
    final capabilities = _bt.capabilities;
    if (!capabilities.peripheralRole) {
      return _set(
        HostStatus.unsupported,
        'This phone cannot run a GATT server or advertise, so it cannot '
        'host. It can still join a party as a seeker.',
      );
    }
    try {
      final statuses = await _bt.requestPermissions(
        BtKit.peripheralPermissions,
      );
      if (describeMissingPermissions(statuses) case final missing?) {
        return _set(HostStatus.needsPermission, missing);
      }
      final server = _server = await _bt.openGattServer(
        services: [
          LocalService(AppUuids.party, [
            _gameCharacteristic,
            _stateCharacteristic,
            _finishCharacteristic,
          ]),
        ],
      );
      if (_disposed) return await _release();
      _subscriptions = server.subscriptionChanges.listen((_) => _changed());
      _advertising = await _bt.startAdvertising(
        AdvertiseOptions(
          serviceUuids: [AppUuids.party],
          localName: capabilities.advertiseLocalName ? 'Party' : null,
          mode: AdvertiseMode.lowLatency,
        ),
      );
      if (_disposed) return await _release();
      _set(HostStatus.open);
    } on BluetoothException catch (e) {
      await _release();
      _set(HostStatus.failed, describeBluetoothError(e));
    }
  }

  void startRound() {
    _game = _game.start();
    _goAt = DateTime.now();
    _publish();
  }

  /// Back to the lobby, for example to hide the target again.
  void endRound() {
    _game = _game.reset();
    _goAt = null;
    _publish();
  }

  void _onFinish(WriteRequest request) {
    final PartyFinish finish;
    try {
      finish = PartyFinish.decode(request.value);
    } on FormatException {
      throw GattException(GattError.valueNotAllowed, 'finish');
    }
    if (_game.phase != PartyPhase.go || finish.round != _game.round) return;
    _game = _game.finish(PartyResult(finish.player, finish.time));
    Timer.run(_publish);
  }

  void _publish() {
    _changed();
    unawaited(_notify());
  }

  Future<void> _notify() async {
    final server = _server;
    if (server == null || server.isClosed) return;
    try {
      await server.notify(_stateCharacteristic, _game.state.encode());
    } on BluetoothException catch (_) {}
  }

  Future<void> _sayGoodbye() async {
    if (_server == null) return;
    _game = _game.close();
    await _notify().timeout(_goodbyeTimeout, onTimeout: () {});
  }

  Future<void> _release() async {
    final advertising = _advertising;
    final subscriptions = _subscriptions;
    final server = _server;
    _advertising = null;
    _subscriptions = null;
    _server = null;
    await _quietly(advertising?.stop());
    await subscriptions?.cancel();
    await _quietly(server?.close());
  }

  static Future<void> _quietly(Future<void>? action) async {
    try {
      await action;
    } on BluetoothException catch (_) {}
  }

  void _set(HostStatus status, [String? message]) {
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
    unawaited(_sayGoodbye().whenComplete(_release));
    super.dispose();
  }
}
