import 'dart:async';
import 'dart:ui' show CallbackHandle, PluginUtilities;

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:logging/logging.dart';

import '../accessories/external_accessories.dart';
import '../audio/audio_profiles.dart';
import '../background/background_event.dart';
import '../channels/byte_channel.dart';
import '../classic/classic_bluetooth.dart';
import '../companion/companion_devices.dart';
import '../core/bluetooth_uuid.dart';
import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../core/operation_queue.dart';
import '../models/adapter_state.dart';
import '../models/advertise_options.dart';
import '../models/bt_kit_options.dart';
import '../models/capabilities.dart';
import '../models/bluetooth_connection_state.dart';
import '../models/permission.dart';
import '../models/scan_options.dart';
import '../models/system_connection.dart';
import '../peripheral_role/advertising_session.dart';
import '../peripheral_role/gatt_server.dart';
import '../peripheral_role/local_gatt.dart';
import '../platform/background_backend.dart';
import '../platform/central_backend.dart';
import 'advertisement.dart';
import 'device_host.dart';
import 'device_list.dart';
import 'native_types.dart';
import 'peripheral.dart';
import 'peripheral_event.dart';
import 'restored_state.dart';
import 'scan_session.dart';

part 'bt_kit_background.dart';

/// The entry point of the unified API.
///
/// ```dart
/// final bt = BtKit.instance;
/// await bt.requestPermissions();
/// await for (final ad in bt.scan(ScanOptions(services: [heartRate]))) {
///   await ad.peripheral.connect();
///   break;
/// }
/// ```
final class BtKit {
  BtKit._(this._backend);

  static BtKit? _instance;

  static BtKit get instance => _instance ??= BtKit._(CentralBackend());

  /// Sets options the platform fixes when bt_kit creates its managers, and
  /// creates them. Call it once, before anything else uses bt_kit, such as
  /// first thing in `main`; afterwards it throws [StateError].
  ///
  /// With a restore identifier, iOS state restoration starts here, so call
  /// it on every launch, including background relaunches. Android ignores
  /// the options.
  static void configure(BtKitOptions options) {
    if (_instance != null) {
      throw StateError(
        'BtKit.configure must run before BtKit.instance is first used',
      );
    }
    _instance = BtKit._(CentralBackend(options));
  }

  /// Registers the function a headless engine runs for each
  /// [BackgroundEvent] while no engine listens to [backgroundEvents]
  /// (Android).
  ///
  /// [handler] must be a top-level or static function annotated with
  /// `@pragma('vm:entry-point')`. Registration survives restarts; call it
  /// again after changing the handler.
  static Future<void> registerBackgroundHandler(
    BackgroundHandler handler,
  ) async {
    final dispatcher = PluginUtilities.getCallbackHandle(_backgroundMain);
    final callback = PluginUtilities.getCallbackHandle(handler);
    if (callback == null) {
      throw ArgumentError.value(
        handler,
        'handler',
        'Must be a top-level or static function',
      );
    }
    final bt = instance;
    bt._requireBackground();
    bt._backend.background.register(
      dispatcher!.toRawHandle(),
      callback.toRawHandle(),
    );
  }

  /// The lowest level of bt_kit's own log records; [Level.OFF] by default.
  ///
  /// Records go to the `bt_kit.adapter`, `.scan`, `.gatt`, `.server` and
  /// `.l2cap` loggers of `package:logging`, and from there to
  /// `Logger.root.onRecord`, which drops records below the root logger's
  /// level:
  ///
  /// ```dart
  /// BtKit.logLevel = Level.FINE;
  /// Logger.root.level = Level.ALL;
  /// Logger.root.onRecord.listen(print);
  /// ```
  ///
  /// [Level.INFO] covers connections and state changes, [Level.FINE] each
  /// queued operation with its time in the queue and its duration, and
  /// [Level.FINER] the bytes of every value, which can carry personal data.
  /// [Level.WARNING] marks every platform workaround bt_kit applies.
  static Level get logLevel => BtLog.level;

  static set logLevel(Level level) => BtLog.level = level;

  /// The permissions the central role always needs. Scans on Android may
  /// also need [BluetoothPermission.location]; [requestPermissions] adds it
  /// where they do.
  static const centralPermissions = {
    BluetoothPermission.scan,
    BluetoothPermission.connect,
  };

  /// The permissions the peripheral role needs.
  static const peripheralPermissions = {
    BluetoothPermission.advertise,
    BluetoothPermission.connect,
  };

  final CentralBackend _backend;
  late final _scans = ScanSessions(_backend.scan);
  late final _host = _Host(this);
  final _peripheralRole = OperationQueue(log: BtLog.server);
  final _peripherals = <String, WeakReference<Peripheral>>{};
  final _linked = <String, Peripheral>{};
  final _events = StreamController<PeripheralEvent>.broadcast();

  /// Bluetooth Classic discovery, bonding and RFCOMM (Android).
  late final ClassicBluetooth classic = createClassicBluetooth(
    _backend.classic,
    _host,
  );

  /// MFi accessories through ExternalAccessory (iOS).
  late final ExternalAccessories accessories = createExternalAccessories(
    _backend.accessories,
    () => capabilities,
  );

  /// The system companion device picker and its associations.
  late final CompanionDevices companion = createCompanionDevices(
    _backend.companion,
    () => capabilities,
    peripheral,
  );

  /// The state of the system's Bluetooth audio links (Android).
  late final AudioProfiles audio = createAudioProfiles(
    _backend.audio,
    () => capabilities,
    _ensurePermissions,
  );

  /// The Layer 1 adapter object: `BluetoothAdapter` on Android,
  /// `CBCentralManager` on iOS.
  AdapterHandle get native => _backend.native;

  BluetoothCapabilities get capabilities => _backend.capabilities;

  AdapterState get adapterState => _backend.adapterState;

  Stream<AdapterState> get adapterStateChanges => _backend.adapterStates;

  /// The statuses of [permissions]; by default those the central role
  /// needs, including [BluetoothPermission.location] where the app's scans
  /// need it.
  Future<Map<BluetoothPermission, PermissionStatus>> checkPermissions([
    Set<BluetoothPermission>? permissions,
  ]) => _backend.checkPermissions(permissions ?? _centralPermissions);

  /// Shows the system prompt for any permission that can still be asked
  /// for, and returns the resulting statuses; by default those the central
  /// role needs, as in [checkPermissions].
  Future<Map<BluetoothPermission, PermissionStatus>> requestPermissions([
    Set<BluetoothPermission>? permissions,
  ]) => _backend.requestPermissions(permissions ?? _centralPermissions);

  Set<BluetoothPermission> get _centralPermissions => {
    ...centralPermissions,
    ..._backend.scanPermissions,
  };

  /// The name this device shows to other Bluetooth devices (Android).
  Future<String?> adapterName() async {
    if (!capabilities.adapterName) {
      throw const UnsupportedFeatureException(
        'adapterName',
        'This platform does not tell apps the device name',
      );
    }
    await _ensurePermissions(const {BluetoothPermission.connect});
    return _backend.adapterName();
  }

  /// Asks the user to turn Bluetooth on; returns whether they did.
  ///
  /// Android only. Check [BluetoothCapabilities.requestEnable] first.
  Future<bool> requestEnable() async {
    if (!capabilities.requestEnable) {
      throw const UnsupportedFeatureException(
        'requestEnable',
        'This platform does not let apps turn Bluetooth on',
      );
    }
    await _ensurePermissions(const {BluetoothPermission.connect});
    return _backend.requestEnable();
  }

  /// Scans until the subscription is cancelled or [ScanOptions.timeout]
  /// passes.
  ///
  /// Listeners with equal options share one native scan; a scan with other
  /// options fails with [ScanException] while one runs (see [currentScan]).
  /// Fails with [BluetoothPermissionException] or
  /// [BluetoothUnavailableException] when scanning is not possible. On
  /// Android, an app whose manifest does not declare `BLUETOOTH_SCAN` with
  /// `neverForLocation` also needs [BluetoothPermission.location].
  Stream<Advertisement> scan([ScanOptions options = const ScanOptions()]) {
    late final StreamController<Advertisement> controller;
    StreamSubscription<ScanHit>? hits;
    controller = StreamController<Advertisement>(
      onListen: () async {
        try {
          await _ensureReady(_backend.scanPermissions);
          if (!controller.hasListener) return;
          hits = _scans
              .scan(options)
              .listen(
                (hit) => controller.add(_advertisement(hit)),
                onError: controller.addError,
                onDone: controller.close,
              );
        } on BluetoothException catch (e) {
          controller.addError(e);
          await controller.close();
        }
      },
      onPause: () => hits?.pause(),
      onResume: () => hits?.resume(),
      onCancel: () => hits?.cancel(),
    );
    return controller.stream;
  }

  Advertisement _advertisement(ScanHit hit) => Advertisement(
    peripheral: _peripheral(hit.peripheral),
    rssi: hit.rssi,
    data: hit.data,
    receivedAt: DateTime.now(),
    native: hit.native,
  );

  /// Scans and keeps a list of the peripherals found: the latest
  /// advertisement of each, in the order they were first found, so that
  /// rows in a UI stay put.
  ///
  /// Emits at most once per [interval]. With [expireAfter], peripherals
  /// that have not advertised for that long leave the list; that needs
  /// [ScanOptions.allowDuplicates], or every peripheral would expire.
  Stream<List<Advertisement>> scanDevices(
    ScanOptions options, {
    Duration? expireAfter,
    Duration interval = const Duration(milliseconds: 500),
  }) {
    if (expireAfter != null && !options.allowDuplicates) {
      throw ArgumentError(
        'expireAfter needs ScanOptions(allowDuplicates: true)',
        'expireAfter',
      );
    }
    return deviceList(
      scan(options),
      interval: interval,
      expireAfter: expireAfter,
    );
  }

  /// Whether a scan is running.
  bool get isScanning => _scans.isScanning;

  /// The options of the running scan.
  ScanOptions? get currentScan => _scans.current;

  Stream<bool> get scanningChanges => _scans.scanningChanges;

  /// Changes on every peripheral this app knows, starting with the ones it
  /// connects to.
  Stream<PeripheralEvent> get events => _events.stream;

  /// The peripherals this app is connected to.
  ///
  /// [systemPeripherals] also lists those that other apps connected.
  List<Peripheral> get connectedPeripherals => List.unmodifiable(
    _linked.values.where((peripheral) => peripheral.isConnected),
  );

  /// The peripheral with [id], or null if the system does not know it.
  ///
  /// On iOS only peripherals this app has discovered or connected to before
  /// are known.
  Future<Peripheral?> peripheral(String id) async {
    final cached = _linked[id] ?? _peripherals[id]?.target;
    if (cached != null) return cached;
    final backend = await _backend.peripheral(id);
    return backend == null ? null : _peripheral(backend);
  }

  /// Peripherals connected to this device by any app, which this app can
  /// then connect to as well.
  ///
  /// iOS only returns peripherals that expose one of [services].
  Future<List<Peripheral>> systemPeripherals({
    List<BluetoothUuid> services = const [],
  }) async {
    await _ensureReady(const {BluetoothPermission.connect});
    final backends = await _backend.systemPeripherals(services);
    return [for (final backend in backends) _peripheral(backend)];
  }

  /// The LE and dual-mode peripherals this device is bonded with (Android).
  Future<List<Peripheral>> bondedPeripherals() async {
    if (!capabilities.bonding) {
      throw const UnsupportedFeatureException(
        'bonding',
        'iOS does not tell apps which devices are bonded',
      );
    }
    await _ensurePermissions(const {BluetoothPermission.connect});
    final backends = await _backend.bondedPeripherals();
    return [for (final backend in backends) _peripheral(backend)];
  }

  /// Connections and disconnections of any app or the system, such as a
  /// headset the user connects in Settings.
  ///
  /// iOS reports only peripherals that expose one of [services] or have
  /// one of [peripheralIds]; name at least one. Android reports every
  /// device and ignores both.
  Stream<SystemConnectionEvent> systemConnections({
    List<BluetoothUuid> services = const [],
    List<String> peripheralIds = const [],
  }) async* {
    if (!capabilities.systemConnectionEvents) {
      throw const UnsupportedFeatureException(
        'systemConnectionEvents',
        'This platform does not report other apps\' connections',
      );
    }
    await _ensureReady(const {BluetoothPermission.connect});
    yield* _backend.systemConnections(services, peripheralIds).map((event) {
      BtLog.adapter.info(() => '$event');
      return event;
    });
  }

  /// What iOS restored when it relaunched the app in the background; see
  /// [BtKitOptions]. Each listener also gets restorations that happened
  /// before it listened.
  Stream<RestoredState> get restored => _merge([
    _backend.restorations.map(
      (restored) => RestoredCentral([
        for (final backend in restored.peripherals) _restored(backend),
      ], restored.scanServices),
    ),
    _backend.peripheralRole.restorations.map(
      (restored) => RestoredPeripheralRole(
        restored.services,
        advertising: restored.advertising,
      ),
    ),
  ]);

  Peripheral _restored(PeripheralBackend backend) {
    final peripheral = _peripheral(backend);
    if (backend.connectionState == BluetoothConnectionState.connected) {
      _linked[peripheral.id] = peripheral;
    }
    return peripheral;
  }

  /// Background scan results and companion presence delivered to this
  /// engine (Android).
  ///
  /// While an engine listens, events come here; otherwise the system starts
  /// a headless engine for the handler from [registerBackgroundHandler].
  Stream<BackgroundEvent> get backgroundEvents =>
      _backend.background.signals.expand(_backgroundEvents);

  /// Starts a scan that keeps running while the app is not, until
  /// [stopBackgroundScan]; it replaces the previous background scan
  /// (Android).
  ///
  /// Results arrive as [BackgroundScanResult]s, batched by the system.
  /// Android checks the filters itself, so they must not use
  /// `AdvertisementFilter.nameContains`, and there must be at least one:
  /// Android stops unfiltered scans while the screen is off.
  Future<void> startBackgroundScan(ScanOptions options) async {
    _requireBackground();
    final filters = options.allFilters;
    if (filters.isEmpty || filters.any((f) => f.nameContains != null)) {
      throw ArgumentError.value(
        options,
        'options',
        'Background scans need filters Android checks itself; '
            'nameContains is checked in Dart',
      );
    }
    await _ensureReady(_backend.scanPermissions);
    await _backend.background.startScan(options);
    BtLog.background.info(() => 'Background scan started');
  }

  Future<void> stopBackgroundScan() async {
    _requireBackground();
    await _ensurePermissions(const {BluetoothPermission.scan});
    await _backend.background.stopScan();
    BtLog.background.info(() => 'Background scan stopped');
  }

  void _requireBackground() {
    if (!capabilities.backgroundEvents) {
      throw const UnsupportedFeatureException(
        'backgroundEvents',
        'iOS relaunches apps through state restoration instead; see '
            'BtKit.configure',
      );
    }
  }

  /// Opens this device's GATT server with [services].
  Future<GattServer> openGattServer({
    List<LocalService> services = const [],
  }) async {
    await _ensurePeripheralRole(const {BluetoothPermission.connect});
    final server = createGattServer(await _backend.peripheralRole.openServer());
    try {
      for (final service in services) {
        await server.addService(service);
      }
    } on Object {
      await server.close();
      rethrow;
    }
    return server;
  }

  /// Starts advertising and completes once the platform confirms it.
  ///
  /// Options the platform cannot honor fail with
  /// [UnsupportedFeatureException]; see [AdvertiseOptions]. Change what is
  /// advertised with [AdvertisingSession.update].
  Future<AdvertisingSession> startAdvertising(
    AdvertiseOptions options, {
    Duration timeout = const Duration(seconds: 10),
    CancelToken? cancelToken,
  }) async {
    checkAdvertising(capabilities, options);
    await _ensurePeripheralRole(const {BluetoothPermission.advertise});
    final backend = await _startOrRelease(
      'startAdvertising',
      () => _backend.peripheralRole.startAdvertising(options),
      (advertising) => advertising.stop(),
      timeout,
      cancelToken,
    );
    return createAdvertisingSession(
      options,
      backend,
      _peripheralRole,
      () => capabilities,
    );
  }

  /// Publishes an L2CAP channel and returns the server accepting it.
  ///
  /// With [secure], centrals must use an encrypted link.
  Future<L2capServer> publishL2capChannel({
    bool secure = true,
    Duration timeout = const Duration(seconds: 10),
    CancelToken? cancelToken,
  }) async {
    if (!capabilities.l2cap) {
      throw const UnsupportedFeatureException(
        'l2cap',
        'This device does not support L2CAP channels',
      );
    }
    await _ensurePeripheralRole(const {BluetoothPermission.connect});
    final backend = await _startOrRelease(
      'publishL2capChannel',
      () => _backend.peripheralRole.publishL2cap(secure: secure),
      (server) => server.close(),
      timeout,
      cancelToken,
    );
    return createL2capServer(backend);
  }

  /// Runs a one-shot start through the peripheral-role queue. If the caller
  /// stops waiting, whatever the platform starts later is released again.
  Future<T> _startOrRelease<T>(
    String name,
    Future<T> Function() start,
    Future<void> Function(T) release,
    Duration timeout,
    CancelToken? cancelToken,
  ) async {
    Future<T>? starting;
    try {
      return await _peripheralRole.run(
        name,
        () => starting = start(),
        timeout: timeout,
        cancelToken: cancelToken,
      );
    } on BluetoothException catch (e) {
      if (e is OperationTimeoutException || e is OperationCancelledException) {
        unawaited(starting?.then(release, onError: (Object _) {}));
      }
      rethrow;
    }
  }

  Future<void> _ensurePeripheralRole(
    Set<BluetoothPermission> permissions,
  ) async {
    await _ensurePermissions(permissions);
    final state = await _backend.peripheralRole.settledState();
    if (!state.isPoweredOn) throw BluetoothUnavailableException(state);
  }

  /// Peripherals are held weakly, except while linked, so that
  /// [connectedPeripherals] and [events] never lose one.
  Peripheral _peripheral(PeripheralBackend backend) {
    final cached = _linked[backend.id] ?? _peripherals[backend.id]?.target;
    if (cached != null) return cached;
    if (_peripherals.length > 256) {
      _peripherals.removeWhere((_, ref) => ref.target == null);
    }
    final created = createPeripheral(backend, _host);
    _peripherals[backend.id] = WeakReference(created);
    return created;
  }

  void _report(PeripheralEvent event) {
    if (event case ConnectionChanged(:final peripheral, :final state)) {
      if (state == BluetoothConnectionState.disconnected) {
        _linked.remove(peripheral.id);
      } else {
        _linked[peripheral.id] = peripheral;
      }
    }
    _events.add(event);
  }

  Future<void> _ensureReady(Set<BluetoothPermission> permissions) async {
    await _ensurePermissions(permissions);
    final state = await _backend.settledAdapterState();
    if (!state.isPoweredOn) throw BluetoothUnavailableException(state);
  }

  Future<void> _ensurePermissions(Set<BluetoothPermission> permissions) async {
    final statuses = await _backend.checkPermissions(permissions);
    final missing = {
      for (final MapEntry(:key, :value) in statuses.entries)
        if (!value.isGranted) key: value,
    };
    if (missing.isEmpty) return;
    final undeclared = missing.values.contains(PermissionStatus.notDeclared);
    throw BluetoothPermissionException(
      missing,
      undeclared
          ? 'Declare ${missing.keys.map((p) => p.name).join(', ')} in the app '
                '(AndroidManifest.xml or Info.plist); see the bt_kit README'
          : 'Not granted: ${missing.keys.map((p) => p.name).join(', ')}. '
                'Call BtKit.requestPermissions first',
    );
  }
}

final class _Host implements DeviceHost {
  _Host(this._bt);

  final BtKit _bt;

  @override
  BluetoothCapabilities get capabilities => _bt.capabilities;

  @override
  Future<void> ensureReady(Set<BluetoothPermission> permissions) =>
      _bt._ensureReady(permissions);

  @override
  void report(PeripheralEvent event) => _bt._report(event);

  @override
  Future<void> openBluetoothSettings() => _bt._backend.openBluetoothSettings();
}

/// Emits the events of every stream in [streams].
Stream<T> _merge<T>(List<Stream<T>> streams) {
  late final StreamController<T> controller;
  final subscriptions = <StreamSubscription<T>>[];
  controller = StreamController<T>(
    onListen: () {
      for (final stream in streams) {
        subscriptions.add(
          stream.listen(controller.add, onError: controller.addError),
        );
      }
    },
    onCancel: () async {
      final active = [...subscriptions];
      subscriptions.clear();
      await Future.wait([for (final s in active) s.cancel()]);
    },
  );
  return controller.stream;
}

/// Replaces [BtKit.instance], or restores the platform's with null; used by
/// `package:bt_kit/testing.dart` only.
void installBackend(CentralBackend? backend) =>
    BtKit._instance = backend == null ? null : BtKit._(backend);
