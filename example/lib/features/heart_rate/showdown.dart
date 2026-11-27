import 'package:flutter/foundation.dart';

import '../../bluetooth/heart_rate.dart';
import '../../bluetooth/tracked_device.dart';
import 'player.dart';
import 'player_palette.dart';
import 'ranking.dart';

/// The players in the showdown, each with a live link to their strap.
final class Showdown extends ChangeNotifier {
  /// Most phones hold about 6–7 connections at once.
  static const maxPlayers = 6;

  final _players = <Player>[];

  /// Players in the order they joined.
  List<Player> get players => List.unmodifiable(_players);

  /// Players from the highest current heart rate to the lowest.
  List<Player> get leaderboard => rankByBpm(_players, (p) => p.bpm);

  bool get isEmpty => _players.isEmpty;

  bool get isFull => _players.length >= maxPlayers;

  bool contains(String id) => _players.any((p) => p.id == id);

  /// Heart-rate sensors in [devices] that are not playing yet.
  List<TrackedDevice> candidates(Iterable<TrackedDevice> devices) => [
    for (final device in devices)
      if (device.data.serviceUuids.contains(HeartRateUuids.service) &&
          !contains(device.id))
        device,
  ];

  void add(TrackedDevice device) {
    if (isFull || contains(device.id)) return;
    final player = Player(
      peripheral: device.peripheral,
      sensorName: device.displayName,
      name: _nextName(),
      color: PlayerPalette.next(_players.map((p) => p.color)),
    )..addListener(notifyListeners);
    _players.add(player);
    player.start();
    notifyListeners();
  }

  void remove(Player player) {
    if (!_players.remove(player)) return;
    player
      ..removeListener(notifyListeners)
      ..dispose();
    notifyListeners();
  }

  String _nextName() {
    final names = _players.map((p) => p.name).toSet();
    for (var n = 1; ; n++) {
      if (!names.contains('Player $n')) return 'Player $n';
    }
  }

  /// Disconnects every strap.
  @override
  void dispose() {
    for (final player in _players) {
      player.dispose();
    }
    _players.clear();
    super.dispose();
  }
}
