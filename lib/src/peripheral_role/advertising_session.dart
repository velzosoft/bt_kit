import '../central/native_types.dart';
import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/operation_queue.dart';
import '../models/advertise_options.dart';
import '../models/capabilities.dart';
import '../platform/peripheral_role_backend.dart';

/// A running advertisement, started with `BtKit.startAdvertising`.
final class AdvertisingSession {
  AdvertisingSession._(
    this._options,
    this._backend,
    this._queue,
    this._capabilities,
  );

  AdvertiseOptions _options;
  final AdvertisingBackend _backend;
  final OperationQueue _queue;
  final BluetoothCapabilities Function() _capabilities;
  var _active = true;

  /// What is advertised now.
  AdvertiseOptions get options => _options;

  bool get isActive => _active;

  /// `AdvertisingSet` on Android, `CBPeripheralManager` on iOS.
  AdvertisingHandle get native => _backend.native;

  /// Advertises [options] instead, and completes once the platform applied
  /// them.
  ///
  /// Android replaces the data of the running advertising set when only
  /// content changes (service UUIDs, service and manufacturer data, the
  /// transmit power flag and periodic data), and otherwise starts a new set
  /// before stopping the old one. iOS restarts the advertisement. If the
  /// update fails, the previous advertisement keeps running.
  Future<void> update(
    AdvertiseOptions options, {
    Duration timeout = const Duration(seconds: 10),
    CancelToken? cancelToken,
  }) async {
    if (!_active) throw StateError('The advertisement was stopped');
    checkAdvertising(_capabilities(), options);
    await _queue.run(
      'updateAdvertising',
      () => _backend.update(options),
      timeout: timeout,
      cancelToken: cancelToken,
    );
    _options = options;
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    await _backend.stop();
  }
}

/// Fails with [UnsupportedFeatureException] or [ArgumentError] for options
/// this device cannot advertise.
void checkAdvertising(
  BluetoothCapabilities capabilities,
  AdvertiseOptions options,
) {
  if (!capabilities.peripheralRole) {
    throw const UnsupportedFeatureException(
      'peripheralRole',
      'This device cannot advertise',
    );
  }
  if (options.extended && !capabilities.extendedAdvertising) {
    throw const UnsupportedFeatureException(
      'extendedAdvertising',
      'This device does not support extended advertising',
    );
  }
  final periodic = options.periodic;
  if (periodic == null) return;
  if (!capabilities.periodicAdvertising) {
    throw const UnsupportedFeatureException(
      'periodicAdvertising',
      'This device does not support periodic advertising',
    );
  }
  if (!options.extended || options.connectable) {
    throw ArgumentError.value(
      options,
      'options',
      'Periodic advertising needs an extended, non-connectable advertisement',
    );
  }
  if (periodic.interval < PeriodicAdvertising.minInterval ||
      periodic.interval > PeriodicAdvertising.maxInterval) {
    throw ArgumentError.value(
      periodic.interval,
      'interval',
      'Must be from ${PeriodicAdvertising.minInterval} to '
          '${PeriodicAdvertising.maxInterval}',
    );
  }
}

/// Creates an [AdvertisingSession]; used by `BtKit` only. Updates run
/// through [queue], the peripheral role's.
AdvertisingSession createAdvertisingSession(
  AdvertiseOptions options,
  AdvertisingBackend backend,
  OperationQueue queue,
  BluetoothCapabilities Function() capabilities,
) => AdvertisingSession._(options, backend, queue, capabilities);
