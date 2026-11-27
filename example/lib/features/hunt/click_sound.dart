import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// The Geiger click: a 12 ms sample played from a small pool of
/// low-latency players.
final class ClickSound {
  /// Low-latency players are not returned to the pool by themselves.
  static const _release = Duration(milliseconds: 60);

  AudioPool? _pool;
  var _starting = false;
  var _disposed = false;

  Future<void> load() async {
    try {
      final pool = await AudioPool.create(
        source: AssetSource('audio/click.wav'),
        maxPlayers: 4,
        playerMode: PlayerMode.lowLatency,
        audioContext: AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
      if (_disposed) return await pool.dispose();
      _pool = pool;
    } on Exception catch (_) {}
  }

  /// Skips the click if the previous one is still starting, so that clicks
  /// never queue up behind a slow audio system.
  void play(double volume) {
    final pool = _pool;
    if (pool == null || _starting) return;
    _starting = true;
    unawaited(_play(pool, volume));
  }

  Future<void> _play(AudioPool pool, double volume) async {
    try {
      final stop = await pool.start(volume: volume);
      Timer(_release, () => unawaited(stop()));
    } on Exception catch (_) {
    } finally {
      _starting = false;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final pool = _pool;
    _pool = null;
    await pool?.dispose();
  }
}
