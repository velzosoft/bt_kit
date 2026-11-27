import 'dart:async';

import 'package:jni/jni.dart';

import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../models/distance.dart';
import '../../native/android/bindings.dart';
import 'jni_conversions.dart';

/// Distance to one device through `android.ranging` (Android 16, API 36):
/// a `RangingSession` with Channel Sounding or RSSI parameters for the
/// device's address.
///
/// Platform quirks handled here:
/// * The manager is only reachable by class, and the session reports on an
///   `Executor`; the main executor delivers to this isolate's thread.
/// * A session fails to open, or closes, with a reason code only.
/// * Each peer needs a `RangingDevice` UUID; it is derived from the address
///   so that it stays the same for the same device.
Stream<DistanceMeasurement> androidDistance(
  Context context,
  String address,
  DistanceMethod method,
  MeasurementRate rate,
) {
  late final StreamController<DistanceMeasurement> controller;
  RangingSession? session;
  void fail(String message, int reason) {
    if (controller.isClosed) return;
    controller.addError(
      RangingException('$message: ${_reason(reason)}', nativeCode: reason),
    );
    unawaited(controller.close());
  }

  final callback = RangingSession$Callback.implement(
    $RangingSession$Callback(
      onOpened: () {},
      onOpened$async: true,
      onOpenFailed: (reason) =>
          fail('The ranging session did not open', reason),
      onOpenFailed$async: true,
      onStarted: (peer, _) => peer.release(),
      onStarted$async: true,
      onStopped: (peer, _) => peer.release(),
      onStopped$async: true,
      onResults: (peer, data) {
        peer.release();
        final DistanceMeasurement? measurement;
        try {
          measurement = _measurement(data, method);
        } on Object catch (error) {
          BtLog.ranging.warning(() => 'Dropped a ranging result', error);
          return;
        } finally {
          data.release();
        }
        if (measurement != null && !controller.isClosed) {
          controller.add(measurement);
        }
      },
      onResults$async: true,
      onClosed: (reason) {
        if (reason == RangingSession$Callback.REASON_LOCAL_REQUEST) {
          if (!controller.isClosed) unawaited(controller.close());
        } else {
          fail('The ranging session closed', reason);
        }
      },
      onClosed$async: true,
      onDlTdoaResults: (peer, measurement) {
        peer.release();
        measurement.release();
      },
      onDlTdoaResults$async: true,
      onMotionReceived: (peer, motion) {
        peer.release();
        motion.release();
      },
      onMotionReceived$async: true,
    ),
  );

  controller = StreamController<DistanceMeasurement>(
    onListen: () {
      try {
        final manager = context.getSystemService<RangingManager?>(
          RangingManager.type.jClass,
        );
        if (manager == null) {
          throw const UnsupportedFeatureException(
            'rssiRanging',
            'This device has no ranging service',
          );
        }
        final started = guardJni(
          'Creating a ranging session',
          () => manager.createRangingSession(context.mainExecutor!, callback),
        );
        if (started == null) {
          throw const RangingException('Android did not create a session');
        }
        session = started;
        guardJni(
          'Starting ranging',
          () => started.start(_preference(address, method, rate)),
        );
      } on BluetoothException catch (e) {
        controller.addError(e);
        unawaited(controller.close());
      }
    },
    onCancel: () {
      final active = session;
      session = null;
      if (active == null) return;
      guardJni('Stopping ranging', active.stop);
      guardJni('Closing the ranging session', active.close);
    },
  );
  return controller.stream;
}

RangingPreference _preference(
  String address,
  DistanceMethod method,
  MeasurementRate rate,
) {
  final peer = address.toJString();
  final updateRate = switch (rate) {
    MeasurementRate.low => RawRangingDevice.UPDATE_RATE_INFREQUENT,
    MeasurementRate.normal => RawRangingDevice.UPDATE_RATE_NORMAL,
    MeasurementRate.high => RawRangingDevice.UPDATE_RATE_FREQUENT,
  };
  final device = RawRangingDevice$Builder()
    ..setRangingDevice(
      (RangingDevice$Builder()..setUuid(javaUuid(_peerUuid(address)))).build(),
    );
  switch (method) {
    case DistanceMethod.channelSounding:
      device.setCsRangingParams(
        (BleCsRangingParams$Builder(
          peer,
        )..setRangingUpdateRate(updateRate)).build(),
      );
    case DistanceMethod.rssi:
      device.setBleRssiRangingParams(
        (BleRssiRangingParams$Builder(
          peer,
        )..setRangingUpdateRate(updateRate)).build(),
      );
  }
  final config =
      (RawInitiatorRangingConfig$Builder()..addRawRangingDevice(device.build()))
          .build();
  return RangingPreference$Builder(
    RangingPreference.DEVICE_ROLE_INITIATOR,
    config,
  ).build();
}

/// A stable UUID for the device with [address].
BluetoothUuid _peerUuid(String address) => BluetoothUuid.parse(
  '00000000-0000-0000-0000-'
  '${address.replaceAll(':', '').toLowerCase().padLeft(12, '0')}',
);

DistanceMeasurement? _measurement(RangingData data, DistanceMethod method) {
  final distance = data.distance;
  if (distance == null) return null;
  double? angle(RangingMeasurement? measurement) {
    final value = measurement?.measurement;
    measurement?.release();
    return value;
  }

  final measurement = DistanceMeasurement(
    meters: distance.measurement,
    method: method,
    timestamp: DateTime.now(),
    confidence: switch (distance.confidence) {
      RangingMeasurement.CONFIDENCE_HIGH => MeasurementConfidence.high,
      RangingMeasurement.CONFIDENCE_MEDIUM => MeasurementConfidence.medium,
      _ => MeasurementConfidence.low,
    },
    standardDeviation:
        _hasStandardDeviation && data.hasDistanceStandardDeviation()
        ? data.distanceStandardDeviationMeters
        : null,
    azimuth: angle(data.azimuth),
    elevation: angle(data.elevation),
    rssi: data.hasRssi() ? data.rssi : null,
  );
  distance.release();
  return measurement;
}

/// The standard deviation arrived in Android 16 QPR2 (API 36.1); on 36.0
/// the methods are missing.
final bool _hasStandardDeviation = () {
  try {
    JClass.forName('android/ranging/RangingData')
        .instanceMethodId('hasDistanceStandardDeviation', '()Z');
    return true;
  } on Object {
    return false;
  }
}();

String _reason(int reason) => switch (reason) {
  RangingSession$Callback.REASON_LOCAL_REQUEST => 'stopped by the app',
  RangingSession$Callback.REASON_REMOTE_REQUEST => 'stopped by the peer',
  RangingSession$Callback.REASON_UNSUPPORTED => 'not supported',
  RangingSession$Callback.REASON_SYSTEM_POLICY => 'refused by system policy',
  RangingSession$Callback.REASON_NO_PEERS_FOUND => 'the peer was not found',
  _ => 'unknown reason $reason',
};
