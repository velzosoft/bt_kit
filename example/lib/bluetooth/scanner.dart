import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/widgets.dart';

import 'device_kind.dart';
import 'tracked_device.dart';

enum ScanStatus {
  idle,
  scanning,
  bluetoothOff,
  unauthorized,
  unsupported,
  failed,
}

/// The app's single, long-running scan.
///
/// Every screen reads from it instead of starting its own scan: Android
/// throttles apps that restart scans, and bt_kit refuses a second scan with
/// different options. Screens that need every advertisement subscribe to
/// `BtKit.instance.scan(Scanner.options)`, which shares this native scan.
///
/// It scans only while the app is visible and Bluetooth is on. Every
/// advertisement updates its [TrackedDevice]; which devices are around, and
/// when listeners hear about it, comes from `BtKit.scanDevices`: devices
/// silent for [TrackedDevice.forgetAfter] leave, and listeners are notified
/// at most twice a second. [devices] always holds the latest state for code
/// that draws every frame.
final class Scanner extends ChangeNotifier {
  /// [bt] is resolved on first use, so a Scanner can be created where
  /// Bluetooth is unavailable, such as in widget tests.
  Scanner([BtKit? bt]) : _override = bt;

  static const options = ScanOptions(
    allowDuplicates: true,
    mode: ScanMode.lowLatency,
  );
  static const _notifyInterval = Duration(milliseconds: 500);

  final BtKit? _override;
  late final BtKit _bt = _override ?? BtKit.instance;
  final _devices = <String, TrackedDevice>{};
  StreamSubscription<Advertisement>? _scan;
  StreamSubscription<List<Advertisement>>? _around;
  StreamSubscription<AdapterState>? _adapterStates;
  AppLifecycleListener? _lifecycle;
  var _enabled = false;
  var _visible = true;
  var _paused = false;
  var _status = ScanStatus.idle;
  String? _error;
  var _received = 0;

  ScanStatus get status => _status;

  /// Why the scan failed, when [status] is [ScanStatus.failed].
  String? get error => _error;

  Iterable<TrackedDevice> get devices => _devices.values;

  int get count => _devices.length;

  /// Advertisements received since the app started.
  int get received => _received;

  TrackedDevice? operator [](String id) => _devices[id];

  /// Devices sorted from the strongest signal to the weakest.
  List<TrackedDevice> get bySignal =>
      _devices.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));

  /// How many devices of each kind, most common first.
  List<MapEntry<DeviceKind, int>> get breakdown {
    final counts = <DeviceKind, int>{};
    for (final device in _devices.values) {
      counts.update(device.kind, (n) => n + 1, ifAbsent: () => 1);
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Starts scanning now and whenever the app becomes visible again.
  void enable() {
    if (_enabled) return;
    _enabled = true;
    _lifecycle = AppLifecycleListener(onShow: _onShow, onHide: _onHide);
    _adapterStates = _bt.adapterStateChanges.listen(_onAdapterState);
    _start();
  }

  void retry() => _start();

  /// Stops scanning until [resume], so that code such as the Lab can scan
  /// with other options.
  void pause() {
    _paused = true;
    _stop(ScanStatus.idle);
  }

  void resume() {
    _paused = false;
    _start();
  }

  void _onShow() {
    _visible = true;
    _start();
  }

  void _onHide() {
    _visible = false;
    _stop(ScanStatus.idle);
  }

  void _start() {
    if (!_enabled || !_visible || _paused || _scan != null) return;
    _error = null;
    _scan = _bt
        .scan(options)
        .listen(_onAdvertisement, onError: _onError, onDone: _onDone);
    _around = _bt
        .scanDevices(
          options,
          expireAfter: TrackedDevice.forgetAfter,
          interval: _notifyInterval,
        )
        .listen(_onAround, onError: (Object _) {});
    _setStatus(ScanStatus.scanning);
  }

  void _stop(ScanStatus status) {
    unawaited(_scan?.cancel());
    unawaited(_around?.cancel());
    _scan = null;
    _around = null;
    _setStatus(status);
  }

  void _onAdvertisement(Advertisement advertisement) {
    _received++;
    final device = _devices[advertisement.peripheral.id];
    if (device == null) {
      _devices[advertisement.peripheral.id] = TrackedDevice(advertisement);
    } else {
      device.update(advertisement);
    }
  }

  void _onAround(List<Advertisement> around) {
    final ids = {for (final ad in around) ad.peripheral.id};
    _devices.removeWhere((id, _) => !ids.contains(id));
    notifyListeners();
  }

  void _onError(Object error) {
    unawaited(_around?.cancel());
    _scan = null;
    _around = null;
    switch (error) {
      case BluetoothUnavailableException(:final state):
        _setStatus(_statusFor(state));
      case BluetoothPermissionException():
        _setStatus(ScanStatus.unauthorized);
      case BluetoothException(:final message):
        _error = message;
        _setStatus(ScanStatus.failed);
      default:
        _error = '$error';
        _setStatus(ScanStatus.failed);
    }
  }

  void _onDone() {
    if (_scan == null) return;
    unawaited(_around?.cancel());
    _scan = null;
    _around = null;
    _setStatus(ScanStatus.idle);
  }

  void _onAdapterState(AdapterState state) {
    if (state.isPoweredOn) {
      _start();
    } else if (state != AdapterState.turningOn) {
      _stop(_statusFor(state));
    }
  }

  static ScanStatus _statusFor(AdapterState state) => switch (state) {
    AdapterState.unsupported => ScanStatus.unsupported,
    AdapterState.unauthorized => ScanStatus.unauthorized,
    AdapterState.poweredOn => ScanStatus.scanning,
    _ => ScanStatus.bluetoothOff,
  };

  void _setStatus(ScanStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_scan?.cancel());
    unawaited(_around?.cancel());
    unawaited(_adapterStates?.cancel());
    _lifecycle?.dispose();
    super.dispose();
  }
}
