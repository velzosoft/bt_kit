import 'dart:async';
import 'dart:typed_data';

import 'package:jni/jni.dart';

import '../../central/native_types.dart';
import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../core/native_handle.dart';
import '../../models/advertise_options.dart';
import '../../native/android/bindings.dart';
import '../peripheral_role_backend.dart';
import 'jni_conversions.dart';

/// An advertisement on `BluetoothLeAdvertiser`, run as one advertising set
/// at a time.
///
/// Legacy advertisements carry at most 31 bytes, so the device name goes
/// into the scan response. Extended, connectable advertisements cannot
/// have a scan response, so everything goes into the advertisement.
///
/// Updates that keep the parameters change the running set's data; others
/// start a new set and stop the old one once it runs, so a failed update
/// leaves the previous advertisement running.
final class AndroidAdvertising implements AdvertisingBackend {
  AndroidAdvertising._(this._advertiser, this._options, this._set);

  static Future<AndroidAdvertising> start(
    BluetoothLeAdvertiser advertiser,
    AdvertiseOptions options,
  ) async {
    _check(options);
    final set = await _AdvertisingSet.start(advertiser, options);
    return AndroidAdvertising._(advertiser, options, set);
  }

  final BluetoothLeAdvertiser _advertiser;
  AdvertiseOptions _options;
  _AdvertisingSet _set;

  @override
  AdvertisingHandle get native => AndroidHandle(_set.native!);

  @override
  Future<void> update(AdvertiseOptions options) async {
    _check(options);
    if (_sameParameters(_options, options)) {
      await _set.change(_Change.data, _data(options));
      if (options.periodic case final periodic?) {
        await _set.change(_Change.periodicData, _periodicData(periodic));
      }
    } else {
      final next = await _AdvertisingSet.start(_advertiser, options);
      final previous = _set;
      _set = next;
      await previous.stop();
    }
    _options = options;
  }

  @override
  Future<void> stop() => _set.stop();

  static void _check(AdvertiseOptions options) {
    if (options.localName != null) {
      throw const UnsupportedFeatureException(
        'advertiseLocalName',
        'Android advertises the device name only; use includeDeviceName',
      );
    }
  }

  /// Whether [b] can be applied to the set running [a] by changing data
  /// alone.
  static bool _sameParameters(AdvertiseOptions a, AdvertiseOptions b) =>
      a.connectable == b.connectable &&
      a.extended == b.extended &&
      a.mode == b.mode &&
      a.txPower == b.txPower &&
      a.includeDeviceName == b.includeDeviceName &&
      a.periodic?.interval == b.periodic?.interval &&
      a.periodic?.includeTxPower == b.periodic?.includeTxPower;

  static AdvertisingSetParameters _parameters(AdvertiseOptions options) {
    final legacy = !options.extended;
    final builder = AdvertisingSetParameters$Builder()
      ..setLegacyMode(legacy)
      ..setConnectable(options.connectable)
      ..setScannable(
        legacy && (options.connectable || options.includeDeviceName),
      )
      ..setInterval(switch (options.mode) {
        AdvertiseMode.lowLatency => AdvertisingSetParameters.INTERVAL_LOW,
        AdvertiseMode.balanced => AdvertisingSetParameters.INTERVAL_MEDIUM,
        AdvertiseMode.lowPower => AdvertisingSetParameters.INTERVAL_HIGH,
      })
      ..setTxPowerLevel(switch (options.txPower) {
        AdvertiseTxPower.ultraLow =>
          AdvertisingSetParameters.TX_POWER_ULTRA_LOW,
        AdvertiseTxPower.low => AdvertisingSetParameters.TX_POWER_LOW,
        AdvertiseTxPower.medium => AdvertisingSetParameters.TX_POWER_MEDIUM,
        AdvertiseTxPower.high => AdvertisingSetParameters.TX_POWER_HIGH,
      });
    return builder.build()!;
  }

  static AdvertiseData _data(AdvertiseOptions options) => _content(
    includeName: options.extended && options.includeDeviceName,
    includeTxPower: options.includeTxPower,
    serviceUuids: options.serviceUuids,
    serviceData: options.serviceData,
    manufacturerData: options.manufacturerData,
  );

  static AdvertiseData? _scanResponse(AdvertiseOptions options) =>
      !options.extended && options.includeDeviceName
      ? (AdvertiseData$Builder()..setIncludeDeviceName(true)).build()!
      : null;

  static PeriodicAdvertisingParameters _periodicParameters(
    PeriodicAdvertising periodic,
  ) =>
      (PeriodicAdvertisingParameters$Builder()
            ..setIncludeTxPower(periodic.includeTxPower)
            ..setInterval(periodic.interval.inMicroseconds ~/ 1250))
          .build()!;

  /// Android takes the transmit power of periodic advertising from its
  /// parameters; the data must not ask for it.
  static AdvertiseData _periodicData(PeriodicAdvertising periodic) => _content(
    includeName: false,
    includeTxPower: false,
    serviceUuids: periodic.serviceUuids,
    serviceData: periodic.serviceData,
    manufacturerData: periodic.manufacturerData,
  );

  static AdvertiseData _content({
    required bool includeName,
    required bool includeTxPower,
    required List<BluetoothUuid> serviceUuids,
    required Map<BluetoothUuid, Uint8List> serviceData,
    required Map<int, Uint8List> manufacturerData,
  }) {
    final builder = AdvertiseData$Builder()
      ..setIncludeDeviceName(includeName)
      ..setIncludeTxPowerLevel(includeTxPower);
    for (final uuid in serviceUuids) {
      builder.addServiceUuid(_parcelUuid(uuid));
    }
    for (final MapEntry(:key, :value) in serviceData.entries) {
      builder.addServiceData(_parcelUuid(key), JByteArray.of(value));
    }
    for (final MapEntry(:key, :value) in manufacturerData.entries) {
      builder.addManufacturerData(key, JByteArray.of(value));
    }
    return builder.build()!;
  }

  static ParcelUuid _parcelUuid(BluetoothUuid uuid) =>
      ParcelUuid.fromString(uuid.value.toJString())!;
}

enum _Change { data, periodicData }

/// One `AdvertisingSet` and the callback that reports on it.
final class _AdvertisingSet {
  _AdvertisingSet._(this._advertiser);

  static Future<_AdvertisingSet> start(
    BluetoothLeAdvertiser advertiser,
    AdvertiseOptions options,
  ) async {
    final set = _AdvertisingSet._(advertiser);
    final periodic = options.periodic;
    guardJni(
      'Starting to advertise',
      () => advertiser.startAdvertisingSet(
        AndroidAdvertising._parameters(options),
        AndroidAdvertising._data(options),
        AndroidAdvertising._scanResponse(options),
        periodic == null
            ? null
            : AndroidAdvertising._periodicParameters(periodic),
        periodic == null ? null : AndroidAdvertising._periodicData(periodic),
        set._callback,
      ),
    );
    await set._started.future;
    return set;
  }

  static const _stopTimeout = Duration(seconds: 2);

  final BluetoothLeAdvertiser _advertiser;
  final _started = Completer<void>();
  final _stopped = Completer<void>();
  final _changes = <_Change, Completer<int>>{};
  AdvertisingSet? native;

  late final AdvertisingSetCallback _callback =
      AdvertisingSetCallback.implement(
        onAdvertisingSetStarted: (set, txPower, status) {
          if (status == AdvertisingSetCallback.ADVERTISE_SUCCESS) {
            native = set;
            _started.complete();
          } else {
            _started.completeError(
              AdvertisingException(_failure(status), nativeCode: status),
            );
          }
        },
        onAdvertisingSetStopped: (_) {
          if (!_stopped.isCompleted) _stopped.complete();
        },
        onAdvertisingDataSet: (_, status) =>
            _changes.remove(_Change.data)?.complete(status),
        onPeriodicAdvertisingDataSet: (_, status) =>
            _changes.remove(_Change.periodicData)?.complete(status),
      );

  /// Replaces the advertised or periodic data; completes once Android
  /// applied it.
  Future<void> change(_Change change, AdvertiseData data) async {
    final answer = _changes[change] = Completer<int>();
    guardJni('Updating the advertisement', () {
      switch (change) {
        case _Change.data:
          native!.advertisingData = data;
        case _Change.periodicData:
          native!.periodicAdvertisingData = data;
      }
    });
    final status = await answer.future;
    if (status != AdvertisingSetCallback.ADVERTISE_SUCCESS) {
      throw AdvertisingException(_failure(status), nativeCode: status);
    }
  }

  Future<void> stop() async {
    guardJni(
      'Stopping advertising',
      () => _advertiser.stopAdvertisingSet(_callback),
    );
    await _stopped.future.timeout(_stopTimeout, onTimeout: () {});
  }

  static String _failure(int status) => switch (status) {
    AdvertisingSetCallback.ADVERTISE_FAILED_DATA_TOO_LARGE =>
      'The advertisement is too large: legacy advertisements carry 31 bytes, '
          'and data changed while advertising 251. Remove data or use '
          'extended advertising',
    AdvertisingSetCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS =>
      'No advertising slot is free',
    AdvertisingSetCallback.ADVERTISE_FAILED_ALREADY_STARTED =>
      'This advertisement is already running',
    AdvertisingSetCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED =>
      'This device does not support these advertising options',
    _ => 'Advertising failed',
  };
}
