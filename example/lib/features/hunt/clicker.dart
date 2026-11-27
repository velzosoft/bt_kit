import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'click_rate.dart';
import 'click_sound.dart';

/// Clicks and vibrates at the pace [ClickRate] sets for the current
/// strength. Each click is scheduled from the strength at that moment, so
/// the pace follows the signal without waiting out a slow interval.
final class Clicker {
  Clicker({ClickSound? sound}) : _sound = sound ?? ClickSound();

  final ClickSound _sound;
  final soundOn = ValueNotifier(true);
  final vibrationOn = ValueNotifier(true);

  /// Counts clicks, so that the screen can flash in step with them.
  final clicks = ValueNotifier(0);

  Future<void>? _loading;
  double? _strength;
  Timer? _timer;
  DateTime? _lastClick;
  DateTime? _lastVibration;

  Future<void> load() => _loading ??= _sound.load();

  /// The strength to click at, from 0 to 1, or null for silence.
  set strength(double? value) {
    _strength = value;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final strength = _strength;
    if (strength == null) return;
    final lastClick = _lastClick;
    final wait = lastClick == null
        ? Duration.zero
        : ClickRate.interval(strength) - DateTime.now().difference(lastClick);
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _click);
  }

  void _click() {
    final strength = _strength;
    if (strength == null) return;
    final now = DateTime.now();
    _lastClick = now;
    clicks.value++;
    if (soundOn.value) _sound.play(ClickRate.volume(strength));
    if (vibrationOn.value && _mayVibrate(now)) {
      _lastVibration = now;
      unawaited(_vibrate(ClickRate.hapticWeight(strength)));
    }
    _schedule();
  }

  bool _mayVibrate(DateTime now) {
    final last = _lastVibration;
    return last == null ||
        ClickRate.vibrates(sinceLastVibration: now.difference(last));
  }

  static Future<void> _vibrate(HapticWeight weight) => switch (weight) {
    HapticWeight.selection => HapticFeedback.selectionClick(),
    HapticWeight.light => HapticFeedback.lightImpact(),
    HapticWeight.medium => HapticFeedback.mediumImpact(),
    HapticWeight.heavy => HapticFeedback.heavyImpact(),
  };

  void dispose() {
    _timer?.cancel();
    _strength = null;
    soundOn.dispose();
    vibrationOn.dispose();
    clicks.dispose();
    unawaited(_sound.dispose());
  }
}
