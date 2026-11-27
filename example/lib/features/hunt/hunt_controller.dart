import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/widgets.dart';

import '../../bluetooth/scanner.dart';
import 'clicker.dart';
import 'hunt_signal.dart';

/// Follows one device's signal and drives the [clicker].
///
/// It listens to the app's shared scan, filtered to the target, but only
/// while the app is visible, the hunt is not paused and the shared scan is
/// running. A [clicker] passed in outlives the controller.
final class HuntController extends ChangeNotifier {
  HuntController({
    required this.targetId,
    required this.scanner,
    BtKit? bt,
    Clicker? clicker,
  }) : _bt = bt ?? BtKit.instance,
       _ownsClicker = clicker == null,
       clicker = clicker ?? Clicker();

  static const _refresh = Duration(milliseconds: 100);

  final String targetId;
  final Clicker clicker;
  final Scanner scanner;
  final BtKit _bt;
  final bool _ownsClicker;
  final _signal = HuntSignal(DateTime.now());
  AppLifecycleListener? _lifecycle;
  StreamSubscription<Advertisement>? _scan;
  Timer? _refreshTimer;
  var _visible = true;
  var _paused = false;
  var _reading = const HuntReading.searching();

  HuntReading get reading => _reading;

  void start() {
    _lifecycle ??= AppLifecycleListener(
      onShow: () => _setVisible(true),
      onHide: () => _setVisible(false),
    );
    scanner.addListener(_sync);
    unawaited(clicker.load());
    _sync();
  }

  /// Stops listening while another screen covers this one.
  void pause() {
    _paused = true;
    _sync();
  }

  void resume() {
    _paused = false;
    _sync();
  }

  void _setVisible(bool visible) {
    _visible = visible;
    _sync();
  }

  void _sync() {
    final run = _visible && !_paused && scanner.status == ScanStatus.scanning;
    if (run && _scan == null) _listen();
    if (!run && _scan != null) _stopListening();
  }

  void _listen() {
    _signal.restart(DateTime.now());
    _scan = _bt
        .scan(Scanner.options)
        .where((ad) => ad.peripheral.id == targetId)
        .listen(
          (ad) => _signal.add(ad.rssi, ad.receivedAt),
          onError: (Object _) => _stopListening(),
          onDone: _stopListening,
        );
    _refreshTimer = Timer.periodic(_refresh, (_) => _refreshReading());
    _refreshReading();
  }

  void _refreshReading() {
    _reading = _signal.readingAt(DateTime.now());
    clicker.strength = _reading.isLive ? _reading.strength : null;
    notifyListeners();
  }

  void _stopListening() {
    unawaited(_scan?.cancel());
    _scan = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    clicker.strength = null;
  }

  @override
  void dispose() {
    scanner.removeListener(_sync);
    _lifecycle?.dispose();
    _stopListening();
    if (_ownsClicker) clicker.dispose();
    super.dispose();
  }
}
