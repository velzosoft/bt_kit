import 'dart:async';
import 'dart:io';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../device_info.dart';
import '../model/failure_tally.dart';
import '../profile/reference_profile.dart';
import '../profile/stream_command.dart';
import 'reference_gatt.dart';
import 'stream_pump.dart';

enum ServeStatus { stopped, starting, serving, failed }

/// This phone as the Lab reference peripheral: a GATT server with the
/// reference profile, advertised under the Lab service UUID, so that two
/// phones can run the whole suite without a dev kit.
final class ReferencePeripheral extends ChangeNotifier {
  ReferencePeripheral([BtKit? bt]) : _bt = bt ?? BtKit.instance;

  static const _subscriberWait = Duration(seconds: 2);
  static const _databaseChangeDelay = Duration(milliseconds: 200);

  final BtKit _bt;
  var _status = ServeStatus.stopped;
  String? _error;
  ReferenceGatt? _gatt;
  GattServer? _server;
  AdvertisingSession? _advertising;
  StreamPump? _pump;
  Timer? _ticker;
  var _sentBefore = 0;
  var _sendRateHz = 0;
  var _disposed = false;

  ServeStatus get status => _status;

  /// How centrals see this phone while it serves.
  String get advertisedAs => _bt.capabilities.advertiseLocalName
      ? '"${ReferenceProfile.localName}"'
      : "this phone's Bluetooth name";

  String? get error => _error;

  Set<Central> get centrals => _server?.centrals ?? const {};

  int get subscriptions {
    final server = _server;
    final gatt = _gatt;
    if (server == null || gatt == null) return 0;
    return [
      for (final kind in StreamKind.values)
        server.subscribers(gatt.stream(kind)).length,
    ].fold(0, (a, b) => a + b);
  }

  StartStream? get stream => _pump?.command;

  /// Packets sent in the last second.
  int get sendRateHz => _sendRateHz;

  int get sent => _pump?.sent ?? 0;

  int get sendFailures => _pump?.failed ?? 0;

  String? get lastSendError => _pump?.lastError;

  int get reads => _gatt?.reads ?? 0;

  int get writes => _gatt?.writes ?? 0;

  int get errorsAnswered => _gatt?.errors ?? 0;

  GattError? get fault => _gatt?.fault;

  Future<void> start() async {
    if (_status == ServeStatus.starting || _status == ServeStatus.serving) {
      return;
    }
    _setStatus(ServeStatus.starting);
    try {
      final statuses = await _bt.requestPermissions(
        BtKit.peripheralPermissions,
      );
      if (!statuses.values.every((s) => s.isGranted)) {
        return _fail(
          'Allow Bluetooth (Nearby devices) for this app in the system '
          'settings, then try again.',
        );
      }
      if (!_bt.capabilities.peripheralRole) {
        return _fail('This phone cannot act as a Bluetooth peripheral.');
      }
      final gatt = ReferenceGatt(
        info: DeviceInfo.summary(),
        onStreamCommand: _onStreamCommand,
        onDatabaseCommand: _onDatabaseCommand,
      );
      final server = await _bt.openGattServer(
        services: [gatt.includedService, gatt.service],
      );
      if (_abandoned) return await server.close();
      _gatt = gatt;
      _server = server;
      _pump = StreamPump(server.notify);
      final advertising = await _bt.startAdvertising(_advertiseOptions());
      if (_abandoned) return await advertising.stop();
      _advertising = advertising;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _setStatus(ServeStatus.serving);
    } on BluetoothException catch (e) {
      await _teardown();
      _fail(_explain(e));
    }
  }

  /// Whether [stop] or [dispose] came while [start] was still waiting.
  bool get _abandoned => _disposed || _status != ServeStatus.starting;

  Future<void> stop() async {
    await _teardown();
    _setStatus(ServeStatus.stopped);
  }

  AdvertiseOptions _advertiseOptions() {
    final capabilities = _bt.capabilities;
    final namable = capabilities.advertiseLocalName;
    return AdvertiseOptions(
      serviceUuids: [ReferenceProfile.service],
      localName: namable ? ReferenceProfile.localName : null,
      includeDeviceName: !namable,
      manufacturerData: capabilities.advertiseCustomData
          ? {ReferenceProfile.manufacturerId: ReferenceProfile.manufacturerData}
          : const {},
      mode: AdvertiseMode.lowLatency,
    );
  }

  /// Changes the database once the write that asked for it is answered,
  /// so the Services Changed indication follows the write response.
  void _onDatabaseCommand({required bool extraService}) {
    final gatt = _gatt;
    if (gatt == null || gatt.hasExtraService == extraService) return;
    gatt.hasExtraService = extraService;
    unawaited(
      Future<void>.delayed(_databaseChangeDelay, () async {
        final server = _server;
        if (server == null) return;
        try {
          if (extraService) {
            await server.addService(gatt.extraService);
          } else {
            await server.removeService(gatt.extraService);
          }
        } on BluetoothException catch (e) {
          gatt.hasExtraService = !extraService;
          _error = FailureTally.describe(e);
        }
        _changed();
      }),
    );
  }

  void _onStreamCommand(StreamCommand command) {
    switch (command) {
      case StopStream():
        _pump?.stop();
      case StartStream(:final kind):
        unawaited(_startWhenSubscribed(_gatt!.stream(kind), command));
    }
    _changed();
  }

  /// A central enables notifications before it asks for the stream, but
  /// the subscription may reach this server a moment after the command.
  Future<void> _startWhenSubscribed(
    LocalCharacteristic characteristic,
    StartStream command,
  ) async {
    final clock = Stopwatch()..start();
    while ((_server?.subscribers(characteristic).isEmpty ?? false) &&
        clock.elapsed < _subscriberWait) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_server != null && identical(_gatt?.streamCommand, command)) {
      _pump?.start(characteristic, command);
    }
  }

  void _tick() {
    final stream = _pump?.command;
    final gatt = _gatt;
    if (stream != null &&
        gatt != null &&
        (_server?.subscribers(gatt.stream(stream.kind)).isEmpty ?? true)) {
      _pump?.stop();
    }
    _sendRateHz = sent - _sentBefore;
    _sentBefore = sent;
    _changed();
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    _pump?.stop();
    final advertising = _advertising;
    final server = _server;
    _advertising = null;
    _server = null;
    try {
      await advertising?.stop();
    } on BluetoothException catch (_) {}
    await server?.close();
    _sendRateHz = 0;
    _sentBefore = 0;
  }

  static String _explain(BluetoothException error) => switch (error) {
    BluetoothUnavailableException() => 'Turn Bluetooth on, then try again.',
    BluetoothPermissionException() =>
      'Allow Bluetooth (Nearby devices) for this app in the system settings.',
    NativeOperationException() || AdvertisingException() when Platform.isIOS =>
      '${error.message}. iOS allows one GATT server and one advertisement '
          'per app: stop Beacon mode, Party and File beam first.',
    _ => FailureTally.describe(error),
  };

  void _fail(String message) {
    _error = message;
    _setStatus(ServeStatus.failed);
  }

  void _setStatus(ServeStatus status) {
    _status = status;
    if (status != ServeStatus.failed) _error = null;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown());
    super.dispose();
  }
}
