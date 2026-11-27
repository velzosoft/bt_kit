import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../../bluetooth/scanner.dart';
import '../../../bluetooth/bluetooth_errors.dart';
import '../clicker.dart';
import '../hunt_controller.dart';
import 'found_detector.dart';
import 'race_time.dart';

enum RaceStage { countdown, hunting, sending, sent, over }

/// One round on a seeker's phone: the countdown, the hunt for the target,
/// and sending the time once it is found.
final class SeekerRace extends ChangeNotifier {
  SeekerRace({
    required this.round,
    required this.scanner,
    required this.clicker,
    required this.send,
  }) {
    _countdown = Timer(Countdown.length, _begin);
  }

  final int round;
  final Scanner scanner;
  final Clicker clicker;
  final Future<void> Function(Duration time) send;
  final goAt = DateTime.now();
  final _detector = FoundDetector();
  late final Timer _countdown;
  var _stage = RaceStage.countdown;
  HuntController? _hunt;
  String? _targetId;
  Duration? _time;
  String? _error;
  var _ended = false;
  var _disposed = false;

  DateTime get startsAt => goAt.add(Countdown.length);

  RaceStage get stage => _stage;

  /// Follows the target while [stage] is hunting and a target is chosen.
  HuntController? get hunt => _hunt;

  String? get targetId => _targetId;

  /// The time sent to the host.
  Duration? get time => _time;

  /// Why the time could not be sent.
  String? get error => _error;

  /// Whether the signal is strong enough to claim the find by hand.
  bool get canClaim =>
      _stage == RaceStage.hunting &&
      (_hunt?.reading.strength ?? 0) >= FoundDetector.nearEnough;

  set targetId(String? id) {
    if (id == _targetId) return;
    _targetId = id;
    if (_stage == RaceStage.hunting) _follow();
    _changed();
  }

  Future<void> claim() async {
    if (_disposed || _stage != RaceStage.hunting) return;
    final time = _time = DateTime.now().difference(startsAt);
    _stage = RaceStage.sending;
    _error = null;
    _unfollow();
    _changed();
    try {
      await send(time);
      _stage = RaceStage.sent;
    } on BluetoothException catch (e) {
      _error = describeBluetoothError(e);
      _stage = _ended ? RaceStage.over : RaceStage.hunting;
      if (_stage == RaceStage.hunting && !_disposed) _follow();
    }
    _changed();
  }

  /// The host ended the round. A time already on its way still counts.
  void end() {
    _ended = true;
    _countdown.cancel();
    _unfollow();
    if (_stage case RaceStage.countdown || RaceStage.hunting) {
      _stage = RaceStage.over;
    }
    _changed();
  }

  void _begin() {
    _stage = RaceStage.hunting;
    _follow();
    _changed();
  }

  void _follow() {
    _unfollow();
    final id = _targetId;
    if (id == null) return;
    _hunt = HuntController(targetId: id, scanner: scanner, clicker: clicker)
      ..addListener(_onReading)
      ..start();
  }

  void _unfollow() {
    _hunt
      ?..removeListener(_onReading)
      ..dispose();
    _hunt = null;
    _detector.reset();
  }

  void _onReading() {
    final reading = _hunt?.reading;
    if (reading == null) return;
    final found = _detector.update(
      reading.isLive ? reading.strength : null,
      DateTime.now(),
    );
    if (found) Timer.run(() => unawaited(claim()));
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _countdown.cancel();
    _unfollow();
    super.dispose();
  }
}
