import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../bluetooth/device_kind.dart';
import '../../bluetooth/scanner.dart';
import '../../bluetooth/tracked_device.dart';
import 'stay_detector.dart';

/// Feeds the shared scan to a [StayDetector] while the screen is open.
/// Everything it learns lives in memory and is gone once it is disposed.
final class LingeringWatch extends ChangeNotifier {
  LingeringWatch(this._scanner) {
    _scanner.addListener(_onScanner);
    _onScanner();
    _timer = Timer.periodic(interval, (_) => _snapshot());
  }

  static const interval = Duration(seconds: 15);

  /// A device is around if it advertised this recently.
  static const heardWithin = Duration(seconds: 15);

  /// After the scan (re)starts, devices take a moment to be heard again;
  /// a snapshot taken earlier would look like a change of surroundings.
  static const warmUp = Duration(seconds: 15);

  final Scanner _scanner;
  final _detector = StayDetector();
  final _kinds = <String, DeviceKind>{};
  final startedAt = DateTime.now();
  late final Timer _timer;
  DateTime? _scanningSince;
  DateTime? _lastSnapshot;

  int get churnEvents => _detector.churnEvents;

  List<StayedDevice> get flagged => _detector.flagged;

  int get unflaggedStayers => _detector.unflaggedStayers;

  /// Whether snapshots are being taken: the scan runs and has warmed up.
  bool get isWatching {
    final since = _scanningSince;
    return since != null && DateTime.now().difference(since) >= warmUp;
  }

  DateTime? get lastSnapshot => _lastSnapshot;

  /// The kind the device had when last heard; kinds never name a brand.
  DeviceKind kindOf(String id) =>
      _scanner[id]?.kind ?? _kinds[id] ?? DeviceKind.unknown;

  /// The device if it is still being heard.
  TrackedDevice? heardNow(String id) {
    final device = _scanner[id];
    if (device == null) return null;
    return device.silenceAt(DateTime.now()) < heardWithin ? device : null;
  }

  void _onScanner() {
    if (_scanner.status == ScanStatus.scanning) {
      _scanningSince ??= DateTime.now();
    } else {
      _scanningSince = null;
    }
  }

  void _snapshot() {
    if (!isWatching) return notifyListeners();
    final now = DateTime.now();
    final heard = [
      for (final device in _scanner.devices)
        if (device.silenceAt(now) < heardWithin) device,
    ];
    _detector.addSnapshot(now, {for (final device in heard) device.id});
    for (final device in heard) {
      if (_detector.staysOf(device.id) > 0) _kinds[device.id] = device.kind;
    }
    _lastSnapshot = now;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    _scanner.removeListener(_onScanner);
    super.dispose();
  }
}
