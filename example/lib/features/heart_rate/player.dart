import 'dart:async';
import 'dart:ui' show Color;

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../bluetooth/heart_rate.dart';
import '../../bluetooth/reconnector.dart';
import 'short_reason.dart';
import 'panic.dart';

enum PlayerStatus {
  /// Not streaming yet.
  connecting,
  live,

  /// Was live, dropped, and is reconnecting in the background.
  reconnecting,

  /// The device has no heart-rate measurement; nothing more to try.
  unsupported,
}

/// One person in the showdown and the strap they wear.
///
/// Keeps the strap connected and subscribed: when it drops, it reconnects
/// with [Backoff] and subscribes again.
final class Player extends ChangeNotifier {
  Player({
    required this.peripheral,
    required this.sensorName,
    required this._name,
    required this._color,
  });

  final Peripheral peripheral;

  /// The strap's own name, such as "Polar H10 1A2B3C4D".
  final String sensorName;
  final baseline = HeartRateBaseline();

  late final _reconnector = Reconnector(_session, onRetry: _onRetry);

  String _name;
  Color _color;
  var _status = PlayerStatus.connecting;
  String? _problem;
  HeartRateMeasurement? _measurement;
  int? _battery;
  var _disposed = false;

  String get id => peripheral.id;
  String get name => _name;
  Color get color => _color;
  PlayerStatus get status => _status;
  bool get isLive => _status == PlayerStatus.live;

  /// Why the player is not live, such as "Signal lost".
  String? get problem => _problem;

  /// Such as "Live" or "Reconnecting · Signal lost".
  String get statusText {
    final label = switch (_status) {
      PlayerStatus.connecting => 'Connecting',
      PlayerStatus.live => 'Live',
      PlayerStatus.reconnecting => 'Reconnecting',
      PlayerStatus.unsupported => 'Stopped',
    };
    return _problem == null ? label : '$label · $_problem';
  }

  /// The latest measurement, kept while reconnecting.
  HeartRateMeasurement? get measurement => _measurement;

  /// Battery level in percent, when the strap reports it.
  int? get battery => _battery;

  /// The current heart rate; null while not live or without skin contact.
  int? get bpm {
    final bpm = _measurement?.bpm;
    return isLive && bpm != null && bpm > 0 ? bpm : null;
  }

  Panic? get panic {
    final (bpm, base) = (this.bpm, baseline.value);
    return bpm == null || base == null ? null : Panic(bpm, base);
  }

  set name(String value) {
    _name = value;
    _changed();
  }

  set color(Color value) {
    _color = value;
    _changed();
  }

  void start() => unawaited(_keepConnected());

  Future<void> _keepConnected() async {
    try {
      await _reconnector.run();
    } on MissingHeartRateException {
      await _disconnect();
      _status = PlayerStatus.unsupported;
      _problem = 'No heart-rate measurement on this device';
      _changed();
    }
  }

  Future<void> _session(CancelToken cancelToken) async {
    try {
      await peripheral.connect(cancelToken: cancelToken);
      await peripheral.discoverServices(cancelToken: cancelToken);
      final measurement = peripheral.characteristic(
        HeartRateUuids.service,
        HeartRateUuids.measurement,
      );
      if (measurement == null) throw const MissingHeartRateException();
      _battery ??= await _readBattery(cancelToken);
      await for (final value in measurement.subscribe()) {
        _onValue(value);
      }
    } on BluetoothException {
      await _disconnect();
      rethrow;
    }
  }

  /// Battery is optional: only a lost link or a cancellation ends the
  /// session here.
  Future<int?> _readBattery(CancelToken cancelToken) async {
    final level = peripheral.characteristic(
      HeartRateUuids.batteryService,
      HeartRateUuids.batteryLevel,
    );
    if (level == null) return null;
    try {
      final value = await level.read(cancelToken: cancelToken);
      return value.isEmpty ? null : value.first;
    } on BluetoothException catch (e) {
      if (e is DisconnectedException || e is OperationCancelledException) {
        rethrow;
      }
      return null;
    }
  }

  void _onValue(Uint8List value) {
    final measurement = HeartRateMeasurement.parse(value);
    if (measurement == null || _reconnector.isCancelled) return;
    _measurement = measurement;
    baseline.add(measurement.bpm, DateTime.now());
    if (!isLive) {
      _status = PlayerStatus.live;
      _problem = null;
      _reconnector.resetBackoff();
    }
    _changed();
  }

  void _onRetry(BluetoothException? error, Duration delay) {
    _status = _measurement == null
        ? PlayerStatus.connecting
        : PlayerStatus.reconnecting;
    _problem = error == null ? 'Signal lost' : shortReason(error);
    _changed();
  }

  Future<void> _disconnect() async {
    try {
      await peripheral.disconnect();
    } on BluetoothException catch (_) {}
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Stops reconnecting and disconnects the strap.
  @override
  void dispose() {
    _disposed = true;
    _reconnector.cancel();
    unawaited(_disconnect());
    super.dispose();
  }
}

/// The device connected but has no Heart Rate Measurement characteristic.
final class MissingHeartRateException implements Exception {
  const MissingHeartRateException();
}
