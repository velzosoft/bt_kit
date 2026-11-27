import 'dart:async';

import 'advertisement.dart';

/// Folds advertisements into the latest one per peripheral, ordered by first
/// discovery.
///
/// Emits at most once per [interval]. With [expireAfter], drops peripherals
/// whose latest advertisement is older than that.
Stream<List<Advertisement>> deviceList(
  Stream<Advertisement> advertisements, {
  required Duration interval,
  Duration? expireAfter,
  DateTime Function() now = DateTime.now,
}) {
  late final _DeviceList list;
  final controller = StreamController<List<Advertisement>>(
    onListen: () => list.start(),
    onPause: () => list.pause(),
    onResume: () => list.resume(),
    onCancel: () => list.stop(),
  );
  list = _DeviceList(advertisements, controller, interval, expireAfter, now);
  return controller.stream;
}

final class _DeviceList {
  _DeviceList(
    this._source,
    this._out,
    this._interval,
    this._expireAfter,
    this._now,
  );

  final Stream<Advertisement> _source;
  final StreamController<List<Advertisement>> _out;
  final Duration _interval;
  final Duration? _expireAfter;
  final DateTime Function() _now;
  final _devices = <String, Advertisement>{};
  StreamSubscription<Advertisement>? _subscription;
  Timer? _cooldown;
  Timer? _expiry;
  var _pending = false;

  void start() {
    _subscription = _source.listen(
      _add,
      onError: _out.addError,
      onDone: () => unawaited(_finish()),
    );
    if (_expireAfter != null) {
      _expiry = Timer.periodic(_interval, (_) => _expire());
    }
  }

  void pause() => _subscription?.pause();

  void resume() => _subscription?.resume();

  Future<void> stop() async {
    _cooldown?.cancel();
    _expiry?.cancel();
    await _subscription?.cancel();
  }

  void _add(Advertisement advertisement) {
    _devices[advertisement.peripheral.id] = advertisement;
    _changed();
  }

  void _expire() {
    final oldest = _now().subtract(_expireAfter!);
    final count = _devices.length;
    _devices.removeWhere((_, ad) => ad.receivedAt.isBefore(oldest));
    if (_devices.length != count) _changed();
  }

  void _changed() {
    _pending = true;
    if (_cooldown == null) _emit();
  }

  void _emit() {
    _pending = false;
    _out.add(List.unmodifiable(_devices.values));
    _cooldown = Timer(_interval, () {
      _cooldown = null;
      if (_pending) _emit();
    });
  }

  Future<void> _finish() async {
    await stop();
    if (_pending) _out.add(List.unmodifiable(_devices.values));
    await _out.close();
  }
}
