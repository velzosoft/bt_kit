import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:jni/jni.dart';

import '../../background/background_event.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../models/scan_options.dart';
import '../../native/android/bindings.dart';
import '../background_backend.dart';
import '../central_backend.dart';
import 'android_central.dart';
import 'jni_conversions.dart';

/// Events Android delivers while the app may not be running: results of
/// `PendingIntent` scans and companion presence, both handed over by the
/// `BackgroundDelivery` Java class.
///
/// While this engine listens to [signals], it is the delivery target;
/// otherwise `BackgroundDelivery` queues the events and starts a headless
/// engine that runs the registered handler.
final class AndroidBackground implements BackgroundBackend {
  AndroidBackground(this._central);

  final AndroidCentral _central;
  late final _engineId = PlatformDispatcher.instance.engineId!;
  var _acknowledges = false;
  late final _signals = StreamController<BackgroundSignal>.broadcast(
    onListen: () => BackgroundDelivery.setListener(
      _engineId,
      BackgroundDelivery$Listener.implement(
        $BackgroundDelivery$Listener(onEvent: _onEvent, onEvent$async: true),
      ),
      _acknowledges,
    ),
    onCancel: () => BackgroundDelivery.removeListener(_engineId),
  );

  @override
  Future<void> startScan(ScanOptions options) async {
    final scanner = _scanner;
    final intent = BackgroundDelivery.scanIntent(_central.context)!;
    guardJni('Stopping the background scan', () => scanner.stopScan(intent));
    final status = guardJni(
      'Starting a background scan',
      () => scanner.startScan$1(
        _central.nativeFilters(options),
        _central.scanSettings(options),
        intent,
      ),
    );
    intent.release();
    if (status != 0) {
      throw ScanException(
        'The background scan failed to start',
        nativeCode: status,
      );
    }
  }

  @override
  Future<void> stopScan() async {
    final intent = BackgroundDelivery.scanIntent(_central.context);
    guardJni('Stopping the background scan', () => _scanner.stopScan(intent));
    intent?.release();
  }

  @override
  Stream<BackgroundSignal> get signals => _signals.stream;

  @override
  void register(int dispatcherHandle, int handlerHandle) =>
      BackgroundDelivery.setHandles(
        _central.context,
        dispatcherHandle,
        handlerHandle,
      );

  @override
  int? get handlerHandle {
    final handle = BackgroundDelivery.handler(_central.context);
    return handle == 0 ? null : handle;
  }

  @override
  void acknowledgeEvents() => _acknowledges = true;

  @override
  void handled() => BackgroundDelivery.handled();

  BluetoothLeScanner get _scanner =>
      _central.adapter.bluetoothLeScanner ??
      (throw BluetoothUnavailableException(_central.adapterState));

  /// Errors thrown here would vanish in the JNI callback, so they are
  /// logged; an acknowledging engine still acknowledges the event.
  void _onEvent(Intent? intent) {
    if (intent == null) return;
    try {
      final signal = _signal(intent);
      if (signal != null) return _signals.add(signal);
    } on Object catch (error) {
      BtLog.background.warning(() => 'Dropped a background event', error);
    } finally {
      intent.release();
    }
    if (_acknowledges) handled();
  }

  BackgroundSignal? _signal(Intent intent) {
    final action = takeString(intent.action);
    if (action == _presenceAction) {
      final presence = _presence(
        intent.getIntExtra(BackgroundDelivery.EXTRA_PRESENCE, -1),
      );
      if (presence == null) return null;
      return PresenceSignal(
        intent.getIntExtra(BackgroundDelivery.EXTRA_ASSOCIATION_ID, -1),
        presence,
      );
    }
    final results = intent.getParcelableArrayListExtra<ScanResult?>(
      BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT,
      _scanResultClass,
    );
    final error = intent.getIntExtra(BluetoothLeScanner.EXTRA_ERROR_CODE, -1);
    final hits = <ScanHit>[
      for (final result in results?.asDart() ?? const <ScanResult?>[])
        if (result != null) ?_central.hit(result),
    ];
    results?.release();
    return ScanSignal(hits, errorCode: error < 0 ? null : error);
  }

  static CompanionPresence? _presence(int event) => switch (event) {
    DevicePresenceEvent.EVENT_BLE_APPEARED ||
    DevicePresenceEvent.EVENT_SELF_MANAGED_APPEARED =>
      CompanionPresence.appeared,
    DevicePresenceEvent.EVENT_BLE_DISAPPEARED ||
    DevicePresenceEvent.EVENT_SELF_MANAGED_DISAPPEARED =>
      CompanionPresence.disappeared,
    DevicePresenceEvent.EVENT_BT_CONNECTED => CompanionPresence.connected,
    DevicePresenceEvent.EVENT_BT_DISCONNECTED => CompanionPresence.disconnected,
    DevicePresenceEvent.EVENT_ASSOCIATION_REMOVED => CompanionPresence.removed,
    _ => null,
  };

  static final _presenceAction = takeString(BackgroundDelivery.ACTION_PRESENCE);
  static final _scanResultClass = ScanResult.type.jClass;
}
