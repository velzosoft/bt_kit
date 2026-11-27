import 'dart:async';

import 'package:objective_c/objective_c.dart' as objc;

import '../../central/native_types.dart';
import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../core/native_handle.dart';
import '../../models/adapter_state.dart';
import '../../models/bt_kit_options.dart';
import '../../models/capabilities.dart';
import '../../models/bluetooth_connection_state.dart';
import '../../models/permission.dart';
import '../../models/scan_options.dart';
import '../../models/system_connection.dart';
import '../../native/ios/bindings.dart';
import '../accessory_backend.dart';
import '../audio_backend.dart';
import '../background_backend.dart';
import '../central_backend.dart';
import '../classic_backend.dart';
import '../companion_backend.dart';
import '../native_scan_filters.dart';
import '../unsupported.dart';
import 'ios_accessories.dart';
import 'ios_companion.dart';
import 'ios_gatt_client.dart';
import 'ios_peripheral_role.dart';
import 'objc_conversions.dart';

/// The central role on iOS, built on `CBCentralManager`.
///
/// Creating the manager shows the Bluetooth permission prompt, so it is
/// created only once the app asks for permission or is already authorized.
/// With a restore identifier it is created at once when authorized, because
/// iOS delivers `centralManager:willRestoreState:` right after creation.
final class IosCentral implements CentralBackend {
  IosCentral(this._options) : peripheralRole = IosPeripheralRole(_options) {
    if (_options.restoreIdentifier != null && _authorized) _central;
  }

  static const _usageKey = 'NSBluetoothAlwaysUsageDescription';
  static const _accessorySetupKey = 'NSAccessorySetupKitSupports';
  static const _settleTimeout = Duration(seconds: 3);
  static const _unsupported = 'iOS does not offer this to apps';

  final BtKitOptions _options;
  CBCentralManager? _manager;
  StreamController<ScanHit>? _scan;
  final _states = StreamController<AdapterState>.broadcast();
  final _active = <String, IosGattClient>{};
  final _known = <String, WeakReference<IosGattClient>>{};
  final _restorations = StreamController<CentralRestoration>.broadcast();
  CentralRestoration? _restored;
  StreamController<SystemConnectionEvent>? _connectionEvents;

  @override
  final IosPeripheralRole peripheralRole;

  @override
  final ClassicBackend classic = const UnsupportedClassic(
    'iOS reaches Classic devices only as MFi accessories',
  );

  @override
  late final AccessoryBackend accessories = IosAccessories();

  @override
  late final CompanionBackend companion = IosCompanion();

  @override
  final BackgroundBackend background = const UnsupportedBackground(
    'iOS relaunches apps through state restoration instead',
  );

  @override
  final AudioBackend audio = const UnsupportedAudio(
    'iOS keeps audio links to itself',
  );

  /// Every callback is a listener, except `willRestoreState`: restored
  /// peripherals need their delegates before CoreBluetooth delivers the
  /// events that woke the app, so it runs synchronously on the main thread,
  /// which is this isolate's.
  late final CBCentralManagerDelegate _delegate = () {
    final builder = objc.ObjCProtocolBuilder(debugName: 'BtKitCentral');
    CBCentralManagerDelegate$Builder.addToBuilderAsListener(
      builder,
      centralManagerDidUpdateState_: (_) => _stateChanged(),
      centralManager_didDiscoverPeripheral_advertisementData_RSSI_:
          (_, peripheral, data, rssi) => _scan?.add((
            peripheral: client(peripheral),
            rssi: rssi.intValue,
            data: advertisementOf(data),
            native: IosHandle((
              peripheral: peripheral,
              advertisementData: data,
              rssi: rssi,
            )),
          )),
      centralManager_didConnectPeripheral_: (_, peripheral) =>
          _active[_id(peripheral)]?.didConnect(),
      centralManager_didFailToConnectPeripheral_error_: (
        _,
        peripheral,
        error,
      ) => _active.remove(_id(peripheral))?.didFailToConnect(error),
      centralManager_didDisconnectPeripheral_error_: (_, peripheral, error) =>
          _active.remove(_id(peripheral))?.didDisconnect(error),
      centralManager_connectionEventDidOccur_forPeripheral_:
          (_, event, peripheral) => _connectionEvents?.add(
            SystemConnectionEvent(
              deviceId: _id(peripheral),
              connected:
                  event == CBConnectionEvent.CBConnectionEventPeerConnected,
              transport: LinkTransport.le,
              at: DateTime.now(),
            ),
          ),
    );
    CBCentralManagerDelegate$Builder.centralManager_willRestoreState_
        .implementAsBlocking(builder, (_, state) => _restore(state));
    return CBCentralManagerDelegate.as(builder.build());
  }();

  CBCentralManager get _central =>
      _manager ??= CBCentralManager.alloc().initWithDelegate$1(
        _delegate,
        options: <Object, Object>{
          CBCentralManagerOptionShowPowerAlertKey: _options.showPowerAlert,
          if (_options.restoreIdentifier case final identifier?)
            CBCentralManagerOptionRestoreIdentifierKey: identifier.toNSString(),
        }.toNSDictionary(),
      );

  bool get _authorized =>
      CBManager.getAuthorization() ==
      CBManagerAuthorization.CBManagerAuthorizationAllowedAlways;

  @override
  AdapterHandle get native => IosHandle(_central);

  @override
  BluetoothCapabilities get capabilities => BluetoothCapabilities(
    lowEnergy: true,
    classic: false,
    le2MPhy: false,
    leCodedPhy: false,
    extendedAdvertising: CBCentralManager.supportsFeatures(
      CBCentralManagerFeature.CBCentralManagerFeatureExtendedScanAndConnect,
    ),
    periodicAdvertising: false,
    channelSounding: CBCentralManager.supportsFeatures(
      CBCentralManagerFeature.CBCentralManagerFeatureChannelSounding,
    ),
    requestMtu: false,
    connectionPriority: false,
    phy: false,
    notifyMode: false,
    requestEnable: false,
    peripheralRole: true,
    advertiseLocalName: true,
    advertiseCustomData: false,
    l2cap: true,
    bonding: false,
    removeBond: false,
    externalAccessory: true,
    companionDevices: true,
    backgroundEvents: false,
    stateRestoration: true,
    systemConnectionEvents: true,
    rssiRanging: false,
    audioProfiles: false,
    gattCacheRefresh: false,
    adapterName: false,
    serverConnectionPriority: true,
  );

  @override
  Set<BluetoothPermission> get scanPermissions => const {
    BluetoothPermission.scan,
  };

  @override
  Future<String?> adapterName() => throw const UnsupportedFeatureException(
    'adapterName',
    'iOS does not tell apps the device name',
  );

  @override
  AdapterState get adapterState {
    switch (CBManager.getAuthorization()) {
      case CBManagerAuthorization.CBManagerAuthorizationDenied ||
          CBManagerAuthorization.CBManagerAuthorizationRestricted:
        return AdapterState.unauthorized;
      case CBManagerAuthorization.CBManagerAuthorizationNotDetermined
          when _manager == null:
        return AdapterState.unknown;
      default:
        return adapterStateOf(_central.state);
    }
  }

  @override
  Stream<AdapterState> get adapterStates => _states.stream;

  @override
  Future<AdapterState> settledAdapterState() async {
    final state = adapterState;
    if (state != AdapterState.unknown && state != AdapterState.resetting) {
      return state;
    }
    if (_manager == null) return state;
    return _states.stream
        .firstWhere(
          (s) => s != AdapterState.unknown && s != AdapterState.resetting,
        )
        .timeout(_settleTimeout, onTimeout: () => adapterState);
  }

  /// One authorization covers every permission except location, which
  /// CoreBluetooth never needs.
  @override
  Future<Map<BluetoothPermission, PermissionStatus>> checkPermissions(
    Set<BluetoothPermission> permissions,
  ) async => {
    for (final permission in permissions)
      permission: permission == BluetoothPermission.location
          ? PermissionStatus.granted
          : _status(),
  };

  @override
  Future<Map<BluetoothPermission, PermissionStatus>> requestPermissions(
    Set<BluetoothPermission> permissions,
  ) async {
    final bluetooth = permissions.any((p) => p != BluetoothPermission.location);
    if (bluetooth && _status() == PermissionStatus.notDetermined) {
      final answered = _states.stream.firstWhere(
        (_) =>
            CBManager.getAuthorization() !=
            CBManagerAuthorization.CBManagerAuthorizationNotDetermined,
      );
      _central;
      await answered;
    }
    return checkPermissions(permissions);
  }

  @override
  Future<bool> requestEnable() => throw const UnsupportedFeatureException(
    'requestEnable',
    'iOS does not let apps turn Bluetooth on',
  );

  @override
  Stream<ScanHit> scan(ScanOptions options) {
    final controller = StreamController<ScanHit>();
    controller
      ..onListen = () {
        _scan = controller;
        final services = iosNativeServices(options);
        _central.scanForPeripheralsWithServices(
          services == null ? null : objc.NSArray.of(services.map(cbUuid)),
          options: {
            CBCentralManagerScanOptionAllowDuplicatesKey:
                options.allowDuplicates,
          }.toNSDictionary(),
        );
      }
      ..onCancel = () {
        if (_scan != controller) return;
        _scan = null;
        _central.stopScan();
      };
    return controller.stream;
  }

  @override
  Future<PeripheralBackend?> peripheral(String id) async {
    final known = _known[id]?.target;
    if (known != null) return known;
    final uuid = NSUUID.alloc().initWithUUIDString(id.toNSString());
    if (uuid == null) return null;
    await settledAdapterState();
    final found = listOf(
      _central.retrievePeripheralsWithIdentifiers(objc.NSArray.of([uuid])),
      CBPeripheral.as,
    );
    return found.isEmpty ? null : client(found.first);
  }

  @override
  Future<List<PeripheralBackend>> systemPeripherals(
    List<BluetoothUuid> services,
  ) async {
    await settledAdapterState();
    return listOf(
      _central.retrieveConnectedPeripheralsWithServices(
        objc.NSArray.of(services.map(cbUuid)),
      ),
      (o) => client(CBPeripheral.as(o)),
    );
  }

  @override
  Future<List<PeripheralBackend>> bondedPeripherals() =>
      throw const UnsupportedFeatureException('bonding', _unsupported);

  @override
  Future<void> openBluetoothSettings() =>
      throw const UnsupportedFeatureException(
        'bluetoothSettings',
        'iOS does not let apps open the Bluetooth settings',
      );

  /// One registration serves every listener; iOS keeps one set of options
  /// per manager.
  @override
  Stream<SystemConnectionEvent> systemConnections(
    List<BluetoothUuid> services,
    List<String> peripheralIds,
  ) {
    final previous = _connectionEvents;
    if (previous != null) return previous.stream;
    late final StreamController<SystemConnectionEvent> controller;
    controller = _connectionEvents = StreamController.broadcast(
      onListen: () => _central.registerForConnectionEventsWithOptions(
        <Object, Object>{
          if (services.isNotEmpty)
            CBConnectionEventMatchingOptionServiceUUIDs: [
              for (final uuid in services) cbUuid(uuid),
            ],
          if (peripheralIds.isNotEmpty)
            CBConnectionEventMatchingOptionPeripheralUUIDs: [
              for (final id in peripheralIds) ?_nsUuid(id),
            ],
        }.toNSDictionary(),
      ),
      onCancel: () {
        _connectionEvents = null;
        _central.registerForConnectionEventsWithOptions(
          <Object, Object>{
            CBConnectionEventMatchingOptionPeripheralUUIDs: <Object>[],
          }.toNSDictionary(),
        );
        unawaited(controller.close());
      },
    );
    return controller.stream;
  }

  @override
  Stream<CentralRestoration> get restorations async* {
    if (_restored case final restored?) yield restored;
    yield* _restorations.stream;
  }

  void _restore(objc.NSDictionary state) {
    final values = state.asDart();
    final peripherals = listOf(
      values[CBCentralManagerRestoredStatePeripheralsKey] as objc.NSArray?,
      CBPeripheral.as,
    );
    final restored = _restored = (
      peripherals: [
        for (final peripheral in peripherals) _restoredClient(peripheral),
      ],
      scanServices: listOf(
        values[CBCentralManagerRestoredStateScanServicesKey] as objc.NSArray?,
        (o) => uuidOf(CBUUID.as(o)),
      ),
    );
    BtLog.adapter.info(
      () => 'Restored ${restored.peripherals.length} peripherals',
    );
    _restorations.add(restored);
  }

  IosGattClient _restoredClient(CBPeripheral peripheral) {
    final client = this.client(peripheral)..restore();
    if (client.connectionState != BluetoothConnectionState.disconnected) {
      _active[client.id] = client;
    }
    return client;
  }

  static NSUUID? _nsUuid(String id) =>
      NSUUID.alloc().initWithUUIDString(id.toNSString());

  /// The one client for [peripheral], so that every callback reaches it.
  IosGattClient client(CBPeripheral peripheral) {
    final id = _id(peripheral);
    final existing = _active[id] ?? _known[id]?.target;
    if (existing != null) return existing;
    final created = IosGattClient(this, peripheral, id);
    _known[id] = WeakReference(created);
    return created;
  }

  void connect(IosGattClient client, {required bool autoConnect}) {
    _active[client.id] = client;
    _central.connectPeripheral(
      client.peripheral,
      options: autoConnect
          ? {CBConnectPeripheralOptionEnableAutoReconnect: true}
                .toNSDictionary()
          : null,
    );
  }

  void cancelConnection(IosGattClient client) =>
      _central.cancelPeripheralConnection(client.peripheral);

  /// CoreBluetooth drops every connection when Bluetooth turns off without
  /// calling `centralManager:didDisconnectPeripheral:error:`.
  void _stateChanged() {
    final state = adapterState;
    BtLog.adapter.info(() => 'Adapter ${state.name}');
    if (state != AdapterState.poweredOn && _active.isNotEmpty) {
      BtLog.gatt.warning(
        () =>
            'Bluetooth is ${state.name}; ending ${_active.length} '
            'connections that iOS dropped without reporting them',
      );
      final dropped = _active.values.toList();
      _active.clear();
      for (final client in dropped) {
        client.adapterTurnedOff();
      }
    }
    _states.add(state);
  }

  /// Apps that reach their accessories only through AccessorySetupKit need
  /// no usage description; iOS authorizes them per accessory.
  PermissionStatus _status() {
    final bundle = objc.NSBundle.getMainBundle();
    final usage =
        bundle.objectForInfoDictionaryKey(_usageKey.toNSString()) ??
        bundle.objectForInfoDictionaryKey(_accessorySetupKey.toNSString());
    if (usage == null) return PermissionStatus.notDeclared;
    return switch (CBManager.getAuthorization()) {
      CBManagerAuthorization.CBManagerAuthorizationNotDetermined =>
        PermissionStatus.notDetermined,
      CBManagerAuthorization.CBManagerAuthorizationRestricted =>
        PermissionStatus.restricted,
      CBManagerAuthorization.CBManagerAuthorizationDenied =>
        PermissionStatus.permanentlyDenied,
      CBManagerAuthorization.CBManagerAuthorizationAllowedAlways =>
        PermissionStatus.granted,
    };
  }

  static String _id(CBPeripheral peripheral) =>
      peripheral.identifier.UUIDString.toDartString();

  static AdapterState adapterStateOf(CBManagerState state) => switch (state) {
    CBManagerState.CBManagerStateUnknown => AdapterState.unknown,
    CBManagerState.CBManagerStateResetting => AdapterState.resetting,
    CBManagerState.CBManagerStateUnsupported => AdapterState.unsupported,
    CBManagerState.CBManagerStateUnauthorized => AdapterState.unauthorized,
    CBManagerState.CBManagerStatePoweredOff => AdapterState.poweredOff,
    CBManagerState.CBManagerStatePoweredOn => AdapterState.poweredOn,
  };
}
