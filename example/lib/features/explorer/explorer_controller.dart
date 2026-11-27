import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import 'characteristic_controller.dart';

enum ExplorerPhase { connecting, discovering, ready, failed }

/// Connects to one peripheral, discovers its services and keeps a
/// [CharacteristicController] for each characteristic. When the peripheral
/// changes its services, they are discovered again. Disposing it
/// disconnects.
final class ExplorerController extends ChangeNotifier {
  ExplorerController(this.peripheral)
    : _connection = peripheral.connectionState {
    _subscriptions = [
      peripheral.connectionStates.listen(_onConnectionState),
      peripheral.mtuChanges.listen((_) => _changed()),
      peripheral.servicesChanged.listen((_) => unawaited(_rediscover())),
    ];
  }

  static const largestMtu = 517;

  final Peripheral peripheral;
  late final List<StreamSubscription<Object?>> _subscriptions;
  final _characteristics = <GattCharacteristic, CharacteristicController>{};
  var _phase = ExplorerPhase.connecting;
  BluetoothConnectionState _connection;
  BluetoothException? _failure;
  ExplorerPhase? _failedDuring;
  CancelToken? _cancelToken;
  var _services = const <GattService>[];
  int? _rssi;
  var _disposed = false;

  ExplorerPhase get phase => _phase;

  BluetoothConnectionState get connection => _connection;

  bool get isConnected => _connection == BluetoothConnectionState.connected;

  /// Why the last attempt failed, when [phase] is [ExplorerPhase.failed].
  BluetoothException? get failure => _failure;

  /// [ExplorerPhase.connecting] or [ExplorerPhase.discovering].
  ExplorerPhase? get failedDuring => _failedDuring;

  List<GattService> get services => _services;

  CharacteristicController controllerFor(GattCharacteristic characteristic) =>
      _characteristics[characteristic]!;

  int? get rssi => _rssi;

  int get mtu => peripheral.mtu;

  /// Why the link last went down, once it has.
  DisconnectReason? get lastDisconnect => peripheral.lastDisconnect;

  int maximumWriteLength({required bool withResponse}) =>
      peripheral.maximumWriteLength(withResponse: withResponse);

  /// Connects and discovers services; the Cancel button stops either step.
  Future<void> connect() async {
    if (_cancelToken != null) return;
    final cancelToken = _cancelToken = CancelToken();
    _clear();
    _setPhase(ExplorerPhase.connecting);
    try {
      await peripheral.connect(cancelToken: cancelToken);
      _setPhase(ExplorerPhase.discovering);
      _show(await peripheral.discoverServices(cancelToken: cancelToken));
    } on BluetoothException catch (e) {
      _failedDuring = _phase;
      _failure = e;
      _setPhase(ExplorerPhase.failed);
      await peripheral.disconnect();
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() => _cancelToken?.cancel();

  Future<int> readRssi() async {
    final rssi = await peripheral.readRssi();
    _rssi = rssi;
    _changed();
    return rssi;
  }

  Future<int> requestLargestMtu() async {
    final mtu = await peripheral.requestMtu(largestMtu);
    _changed();
    return mtu;
  }

  Future<void> requestHighPriority() =>
      peripheral.requestConnectionPriority(ConnectionPriority.high);

  Future<void> _rediscover() async {
    if (_phase != ExplorerPhase.ready || !isConnected) return;
    try {
      final services = await peripheral.discoverServices();
      _clear();
      _show(services);
    } on BluetoothException catch (_) {}
  }

  void _show(List<GattService> services) {
    if (_disposed) return;
    _services = services;
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        _characteristics[characteristic] = CharacteristicController(
          characteristic,
        );
      }
    }
    _setPhase(ExplorerPhase.ready);
  }

  void _clear() {
    for (final controller in _characteristics.values) {
      controller.dispose();
    }
    _characteristics.clear();
    _services = const [];
    _rssi = null;
  }

  void _onConnectionState(BluetoothConnectionState state) {
    _connection = state;
    if (state == BluetoothConnectionState.disconnected) _rssi = null;
    _changed();
  }

  void _setPhase(ExplorerPhase phase) {
    _phase = phase;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _clear();
    unawaited(peripheral.disconnect());
    super.dispose();
  }
}
