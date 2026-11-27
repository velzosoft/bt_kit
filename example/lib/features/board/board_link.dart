import 'dart:async';
import 'dart:ui' show Color;

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../bluetooth/app_uuids.dart';
import '../../bluetooth/bluetooth_errors.dart';
import '../../bluetooth/reconnector.dart';
import '../../bluetooth/scanner.dart';
import '../../bluetooth/tracked_device.dart';
import 'board_protocol.dart';

enum BoardStatus {
  looking('Looking for a board'),
  choosing('Choose a board'),
  connecting('Connecting'),
  reconnecting('Reconnecting'),
  ready('Ready'),
  linkLost('Link lost'),
  notABoard('Not a bt_kit board');

  const BoardStatus(this.label);

  final String label;
}

/// The link to one Hello board.
///
/// Finds boards in the app's shared scan, connects to the only one or the
/// one the user picks, subscribes to its LED and button, and reconnects
/// with [Backoff] when the link drops. Disposing it disconnects.
final class BoardLink extends ChangeNotifier {
  BoardLink(this._scanner, {BtKit? bt}) : _override = bt;

  static const rssiInterval = Duration(seconds: 2);

  final Scanner _scanner;
  final BtKit? _override;
  late final BtKit _bt = _override ?? BtKit.instance;
  final _buttonEvents = StreamController<ButtonEvent>.broadcast();

  var _status = BoardStatus.looking;
  TrackedDevice? _board;
  Reconnector? _reconnector;
  GattCharacteristic? _ledCommand;
  double? _rssi;
  BoardInfo? _info;
  LedState? _led;
  String? _problem;
  var _wasReady = false;
  var _started = false;
  var _disposed = false;

  BoardStatus get status => _status;

  bool get isReady => _status == BoardStatus.ready;

  /// The board being connected, once there is one.
  TrackedDevice? get board => _board;

  /// Smoothed signal strength in dBm: read from the link while connected,
  /// from the scan before.
  double? get rssi => _rssi ?? _board?.rssi;

  BoardInfo? get info => _info;

  /// What the board's LED shows; a new object for every report, null while
  /// the board is not connected.
  LedState? get led => _led;

  /// Why the link is not ready, such as "Could not connect".
  String? get problem => _problem;

  /// Every press and release, and a hold already in progress on connect.
  Stream<ButtonEvent> get buttonEvents => _buttonEvents.stream;

  /// Boards in the shared scan, strongest signal first.
  List<TrackedDevice> get nearby => [
    for (final device in _scanner.bySignal)
      if (isBoard(device)) device,
  ];

  static bool isBoard(TrackedDevice device) =>
      device.data.serviceUuids.contains(AppUuids.board);

  /// Starts looking: connects at once when one board is around, otherwise
  /// waits in [BoardStatus.choosing] for [choose].
  void start() {
    if (_started) return;
    _started = true;
    _scanner.addListener(_onScan);
    _onScan();
  }

  /// Connects to [device], leaving the board connected before.
  void choose(TrackedDevice device) {
    if (_disposed || (_board?.id == device.id && _reconnector != null)) {
      return;
    }
    _reconnector?.cancel();
    _board = device;
    _rssi = null;
    _info = null;
    _led = null;
    _problem = null;
    _wasReady = false;
    late final Reconnector reconnector;
    reconnector = Reconnector(
      (token) => _session(device.peripheral, reconnector, token),
      onRetry: (error, _) => _onRetry(reconnector, error),
    );
    _reconnector = reconnector;
    _setStatus(BoardStatus.connecting);
    unawaited(_run(reconnector));
  }

  /// Flashes the board's LED three times in [color]. Returns why it did not
  /// work, or null.
  Future<String?> blink(Color color) async {
    final command = _ledCommand;
    if (command == null) return 'The board is not connected.';
    try {
      await command.write(BlinkCommand(color).encode());
      return null;
    } on BluetoothException catch (e) {
      return describeBluetoothError(e);
    }
  }

  void _onScan() {
    if (_board != null) return;
    final boards = nearby;
    if (boards.isEmpty) {
      _setStatus(BoardStatus.looking);
    } else if (boards.length == 1 && _status == BoardStatus.looking) {
      choose(boards.single);
    } else {
      _setStatus(BoardStatus.choosing);
    }
  }

  Future<void> _run(Reconnector reconnector) async {
    try {
      await reconnector.run();
    } on MissingBoardServiceException {
      if (_reconnector != reconnector) return;
      _problem = 'It has no Hello board service.';
      _setStatus(BoardStatus.notABoard);
    }
  }

  Future<void> _session(
    Peripheral peripheral,
    Reconnector reconnector,
    CancelToken token,
  ) async {
    final subscriptions = <StreamSubscription<Uint8List>>[];
    Timer? rssiTimer;
    try {
      _setStatus(_wasReady ? BoardStatus.reconnecting : BoardStatus.connecting);
      await peripheral.connect(cancelToken: token);
      await _prioritize(peripheral, token);
      await peripheral.discoverServices(cancelToken: token);
      final board = _BoardCharacteristics.of(peripheral);
      _info = BoardInfo.parse(await board.info.read(cancelToken: token));

      final dropped = Completer<void>();
      dropped.future.ignore();
      void end([Object? error]) {
        if (dropped.isCompleted) return;
        error == null ? dropped.complete() : dropped.completeError(error);
      }

      unawaited(token.whenCancelled.then((_) => end()));
      subscriptions.add(
        board.led.subscribe().listen(
          (value) => _onLed(value, token),
          onError: end,
          onDone: end,
        ),
      );
      _onLed(await board.led.read(cancelToken: token), token);

      var heardButton = false;
      subscriptions.add(
        board.button.subscribe().listen(
          (value) {
            heardButton = true;
            _onButton(value, token);
          },
          onError: end,
          onDone: end,
        ),
      );
      final current = ButtonEvent.parse(
        await board.button.read(cancelToken: token),
      );
      token.throwIfCancelled();
      if (current != null && current.pressed && !heardButton) {
        _buttonEvents.add(current);
      }

      _ledCommand = board.ledCommand;
      _wasReady = true;
      _problem = null;
      reconnector.resetBackoff();
      _setStatus(BoardStatus.ready);
      rssiTimer = Timer.periodic(
        rssiInterval,
        (_) => _readRssi(peripheral, token),
      );
      await dropped.future;
    } finally {
      rssiTimer?.cancel();
      if (_reconnector == reconnector) _ledCommand = null;
      await _disconnect(peripheral);
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    }
  }

  Future<void> _prioritize(Peripheral peripheral, CancelToken token) async {
    if (!_bt.capabilities.connectionPriority) return;
    try {
      await peripheral.requestConnectionPriority(
        ConnectionPriority.high,
        cancelToken: token,
      );
    } on BluetoothException catch (e) {
      if (e is DisconnectedException || e is OperationCancelledException) {
        rethrow;
      }
    }
  }

  void _onLed(Uint8List value, CancelToken token) {
    final led = LedState.parse(value);
    if (led == null || token.isCancelled) return;
    _led = led;
    _changed();
  }

  void _onButton(Uint8List value, CancelToken token) {
    final event = ButtonEvent.parse(value);
    if (event == null || token.isCancelled || _buttonEvents.isClosed) return;
    _buttonEvents.add(event);
  }

  Future<void> _readRssi(Peripheral peripheral, CancelToken token) async {
    try {
      final rssi = await peripheral.readRssi(cancelToken: token);
      if (token.isCancelled) return;
      _rssi = rssi.toDouble();
      _changed();
    } on BluetoothException catch (_) {}
  }

  void _onRetry(Reconnector reconnector, BluetoothException? error) {
    if (_reconnector != reconnector) return;
    _led = null;
    _rssi = null;
    _problem = error == null || error is DisconnectedException
        ? null
        : describeBluetoothError(error);
    _setStatus(_wasReady ? BoardStatus.linkLost : BoardStatus.connecting);
  }

  Future<void> _disconnect(Peripheral peripheral) async {
    try {
      await peripheral.disconnect();
    } on BluetoothException catch (_) {}
  }

  void _setStatus(BoardStatus status) {
    _status = status;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Stops reconnecting and disconnects the board.
  @override
  void dispose() {
    _disposed = true;
    _scanner.removeListener(_onScan);
    _reconnector?.cancel();
    unawaited(_buttonEvents.close());
    super.dispose();
  }
}

/// The device connected but does not serve the Hello board service.
final class MissingBoardServiceException implements Exception {
  const MissingBoardServiceException();
}

final class _BoardCharacteristics {
  const _BoardCharacteristics(
    this.button,
    this.ledCommand,
    this.led,
    this.info,
  );

  static _BoardCharacteristics of(Peripheral peripheral) {
    GattCharacteristic find(BluetoothUuid uuid) =>
        peripheral.characteristic(AppUuids.board, uuid) ??
        (throw const MissingBoardServiceException());
    return _BoardCharacteristics(
      find(AppUuids.boardButton),
      find(AppUuids.boardLedCommand),
      find(AppUuids.boardLed),
      find(AppUuids.boardInfo),
    );
  }

  final GattCharacteristic button;
  final GattCharacteristic ledCommand;
  final GattCharacteristic led;
  final GattCharacteristic info;
}
