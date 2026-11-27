part of 'peripheral.dart';

extension on Peripheral {
  Stream<Uint8List> _subscribe(
    GattCharacteristic characteristic,
    NotifyMode requested,
  ) {
    final NotifyMode mode;
    try {
      if (characteristic.service.isInvalidated) throw Peripheral._invalidated;
      mode = _notifyMode(characteristic, requested);
    } on BluetoothException catch (e) {
      return Stream.error(e);
    }
    final key = characteristic._key;
    final existing = _subscriptions[key];
    if (existing != null && existing.mode == mode) return existing.stream;
    if (existing != null && existing.isActive) {
      throw StateError(
        '${characteristic.uuid} already has a ${existing.mode.name} '
        'subscription; cancel it before asking for ${mode.name}',
      );
    }
    existing?.end(null);
    return (_subscriptions[key] = _Subscription(characteristic, mode)).stream;
  }

  NotifyMode _notifyMode(GattCharacteristic characteristic, NotifyMode mode) {
    final properties = characteristic.properties;
    if (mode == NotifyMode.auto) {
      return properties.notify
          ? NotifyMode.notification
          : NotifyMode.indication;
    }
    final supported = mode == NotifyMode.notification
        ? properties.notify
        : properties.indicate;
    if (!supported) {
      throw UnsupportedFeatureException(
        mode.name,
        '${characteristic.uuid} does not support ${mode.name}s',
      );
    }
    if (properties.notify &&
        properties.indicate &&
        !_host.capabilities.notifyMode) {
      throw const UnsupportedFeatureException(
        'notifyMode',
        'This platform chooses between notification and indication itself',
      );
    }
    return mode;
  }

  Future<void> _setNotifying(
    GattCharacteristic characteristic,
    NotifyMode? mode,
  ) => _runOn(
    characteristic.service,
    mode == null
        ? 'unsubscribe ${characteristic.uuid}'
        : 'subscribe ${characteristic.uuid} (${mode.name})',
    () => _backend.setNotifying(characteristic._discovered, mode),
    Timeouts.gatt,
    null,
  );
}

/// The pushes of one characteristic, shared by every listener. They are
/// turned on for the first listener and off after the last one leaves.
final class _Subscription {
  _Subscription(this._characteristic, this.mode) {
    _controller = StreamController<Uint8List>.broadcast(
      onListen: _enable,
      onCancel: _disable,
    );
  }

  final GattCharacteristic _characteristic;
  final NotifyMode mode;
  late final StreamController<Uint8List> _controller;
  var isEnabled = false;

  Peripheral get _peripheral => _characteristic.peripheral;

  Stream<Uint8List> get stream => _controller.stream;

  bool get isActive => _controller.hasListener;

  void add(Uint8List value) {
    if (!_controller.isClosed) _controller.add(value);
  }

  /// Ends the stream, with [error] for any listener.
  void end(BluetoothException? error) {
    isEnabled = false;
    if (_controller.isClosed) return;
    if (error != null && _controller.hasListener) _controller.addError(error);
    unawaited(_controller.close());
  }

  void _enable() => unawaited(
    _peripheral
        ._setNotifying(_characteristic, mode)
        .then((_) => isEnabled = isActive, onError: _fail),
  );

  void _disable() {
    if (!_peripheral.isConnected) {
      isEnabled = false;
      return;
    }
    unawaited(
      _peripheral
          ._setNotifying(_characteristic, null)
          .then((_) => isEnabled = false, onError: (Object _) {}),
    );
  }

  void _fail(Object error) {
    if (!_controller.isClosed) _controller.addError(error);
  }
}
