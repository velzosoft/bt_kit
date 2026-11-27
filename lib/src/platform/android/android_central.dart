import 'dart:async';
import 'dart:collection';

import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';

import '../../central/native_types.dart';
import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../core/native_handle.dart';
import '../../models/adapter_state.dart';
import '../../models/advertisement_data.dart';
import '../../models/advertisement_filter.dart';
import '../../models/capabilities.dart';
import '../../models/permission.dart';
import '../../models/scan_options.dart';
import '../../models/system_connection.dart';
import '../../native/android/bindings.dart';
import '../accessory_backend.dart';
import '../audio_backend.dart';
import '../background_backend.dart';
import '../central_backend.dart';
import '../classic_backend.dart';
import '../native_scan_filters.dart';
import '../peripheral_role_backend.dart';
import '../unsupported.dart';
import 'android_activity.dart';
import 'android_audio.dart';
import 'android_background.dart';
import 'android_bonds.dart';
import 'android_broadcasts.dart';
import 'android_classic.dart';
import 'android_companion.dart';
import 'android_gatt_client.dart';
import 'android_peripheral_role.dart';
import 'android_permissions.dart';
import 'jni_conversions.dart';

/// The central role on Android, built on `BluetoothManager`,
/// `BluetoothLeScanner` and `BluetoothGatt`.
final class AndroidCentral implements CentralBackend {
  AndroidCentral() : _context = androidApplicationContext.as(Context.type);

  /// Android silently returns no results after an app starts more than five
  /// scans within 30 seconds.
  static const _scanStartLimit = 5;
  static const _scanStartWindow = Duration(seconds: 30);
  static const _rangingApi = 36;
  static const _bluetoothSettings = 'android.settings.BLUETOOTH_SETTINGS';

  final Context _context;
  late final _activity = AndroidActivity();
  late final _permissions = AndroidPermissions(_context, _activity);
  late final BluetoothManager? _manager = _context
      .getSystemService$1(Context.BLUETOOTH_SERVICE!)
      ?.as(BluetoothManager.type, releaseOriginal: true);
  late final BluetoothAdapter? _adapter = _manager?.adapter;
  late final _adapterStates = StreamController<AdapterState>.broadcast(
    onListen: _registerStateReceiver,
    onCancel: _unregisterStateReceiver,
  );
  final _scanStarts = Queue<DateTime>();
  BroadcastReceiver? _stateReceiver;

  Context get context => _context;

  late final bonds = AndroidBonds(_context);

  late final bool _hasRangingService =
      Build$VERSION.SDK_INT >= _rangingApi &&
      _context.getSystemService<JObject?>(RangingManager.type.jClass) != null;

  @override
  late final AndroidCompanion companion = AndroidCompanion(_context, _activity);

  @override
  late final ClassicBackend classic = AndroidClassic(this);

  @override
  final AccessoryBackend accessories = const UnsupportedAccessories(
    'ExternalAccessory is an iOS API',
  );

  @override
  late final BackgroundBackend background = AndroidBackground(this);

  @override
  late final AudioBackend audio = AndroidAudio(this);

  BluetoothManager get manager =>
      _manager ??
      (throw BluetoothUnavailableException(AdapterState.unsupported));

  BluetoothAdapter get adapter =>
      _adapter ??
      (throw BluetoothUnavailableException(AdapterState.unsupported));

  @override
  late final PeripheralRoleBackend peripheralRole = AndroidPeripheralRole(this);

  @override
  AdapterHandle get native => AndroidHandle(adapter);

  @override
  BluetoothCapabilities get capabilities {
    final packages = _context.packageManager!;
    bool feature(JString? name) =>
        name != null && packages.hasSystemFeature(name);
    final adapter = _adapter;
    return BluetoothCapabilities(
      lowEnergy: feature(PackageManager.FEATURE_BLUETOOTH_LE),
      classic: feature(PackageManager.FEATURE_BLUETOOTH),
      le2MPhy: adapter?.isLe2MPhySupported ?? false,
      leCodedPhy: adapter?.isLeCodedPhySupported ?? false,
      extendedAdvertising: adapter?.isLeExtendedAdvertisingSupported ?? false,
      periodicAdvertising: adapter?.isLePeriodicAdvertisingSupported ?? false,
      channelSounding:
          Build$VERSION.SDK_INT >= _rangingApi &&
          feature(PackageManager.FEATURE_BLUETOOTH_LE_CHANNEL_SOUNDING),
      requestMtu: true,
      connectionPriority: true,
      phy: true,
      notifyMode: true,
      requestEnable: adapter != null,
      peripheralRole: adapter?.isMultipleAdvertisementSupported ?? false,
      advertiseLocalName: false,
      advertiseCustomData: true,
      l2cap: adapter != null,
      bonding: adapter != null,
      removeBond: adapter != null && AndroidCompanion.canRemoveBonds,
      externalAccessory: false,
      companionDevices: feature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP),
      backgroundEvents: adapter != null,
      stateRestoration: false,
      systemConnectionEvents: adapter != null,
      rssiRanging: _hasRangingService,
      audioProfiles: adapter != null,
      gattCacheRefresh: adapter != null,
      adapterName: adapter != null,
      serverConnectionPriority: false,
    );
  }

  @override
  Set<BluetoothPermission> get scanPermissions => {
    BluetoothPermission.scan,
    if (_permissions.scanNeedsLocation) BluetoothPermission.location,
  };

  @override
  Future<String?> adapterName() async =>
      guardJni('Reading the adapter name', () => takeString(adapter.name));

  @override
  AdapterState get adapterState =>
      _adapter == null ? AdapterState.unsupported : _state(_adapter.state);

  @override
  Stream<AdapterState> get adapterStates => _adapterStates.stream;

  @override
  Future<AdapterState> settledAdapterState() async {
    final state = adapterState;
    if (state != AdapterState.turningOn && state != AdapterState.turningOff) {
      return state;
    }
    return adapterStates
        .firstWhere(
          (s) => s == AdapterState.poweredOn || s == AdapterState.poweredOff,
        )
        .timeout(const Duration(seconds: 10), onTimeout: () => adapterState);
  }

  @override
  Future<Map<BluetoothPermission, PermissionStatus>> checkPermissions(
    Set<BluetoothPermission> permissions,
  ) async => _permissions.check(permissions);

  @override
  Future<Map<BluetoothPermission, PermissionStatus>> requestPermissions(
    Set<BluetoothPermission> permissions,
  ) => _permissions.request(permissions);

  @override
  Future<void> openBluetoothSettings() async {
    final intent = Intent.new$3(_bluetoothSettings.toJString());
    await _activity.startForResult(intent);
    intent.release();
  }

  @override
  Future<bool> requestEnable() async {
    adapter;
    final intent = Intent.new$3(BluetoothAdapter.ACTION_REQUEST_ENABLE);
    final result = await _activity.startForResult(intent);
    intent.release();
    return result == AndroidActivity.resultOk;
  }

  @override
  Stream<ScanHit> scan(ScanOptions options) {
    final controller = StreamController<ScanHit>();
    BluetoothLeScanner? scanner;
    ScanCallback? callback;

    void deliver(ScanResult? result) {
      final hit = result == null ? null : _hit(result);
      if (hit != null) controller.add(hit);
    }

    void fail(BluetoothException error) {
      if (controller.isClosed) return;
      controller.addError(error);
      unawaited(controller.close());
    }

    controller
      ..onListen = () async {
        try {
          await _reserveScanStart();
          if (!controller.hasListener) return;
          final active = scanner = adapter.bluetoothLeScanner;
          if (active == null) {
            throw BluetoothUnavailableException(adapterState);
          }
          final results = callback = ScanCallback.implement(
            onScanResult: (_, result) => deliver(result),
            onBatchScanResults: (results) => results?.asDart().forEach(deliver),
            onScanFailed: (code) => fail(
              ScanException('The scan failed to start', nativeCode: code),
            ),
          );
          final failures = ScanThread$Listener.implement(
            $ScanThread$Listener(
              onStartFailed: (permissionDenied, message) => fail(
                _scanStartFailure(permissionDenied, takeString(message)),
              ),
              onStartFailed$async: true,
            ),
          );
          guardJni(
            'Starting a scan',
            () => ScanThread.startScan(
              active,
              _filters(options),
              _settings(options),
              results,
              failures,
            ),
          );
        } on BluetoothException catch (e) {
          fail(e);
        }
      }
      ..onCancel = () {
        final active = callback;
        if (active != null) {
          guardJni(
            'Stopping a scan',
            () => ScanThread.stopScan(scanner, active),
          );
        }
      };
    return controller.stream;
  }

  static BluetoothException _scanStartFailure(
    bool permissionDenied,
    String? message,
  ) {
    final description = 'Starting a scan failed: $message';
    return permissionDenied
        ? BluetoothPermissionException(const {}, description)
        : NativeOperationException(description);
  }

  @override
  Future<PeripheralBackend?> peripheral(String id) async {
    if (!BluetoothAdapter.checkBluetoothAddress(id.toJString())) return null;
    final device = adapter.getRemoteDevice$1(id.toJString());
    return device == null ? null : AndroidGattClient(this, device, id);
  }

  @override
  Future<List<PeripheralBackend>> systemPeripherals(
    List<BluetoothUuid> services,
  ) async {
    final devices = guardJni(
      'Listing connected devices',
      () => manager.getConnectedDevices(BluetoothProfile.GATT),
    );
    return [
      for (final device in devices?.asDart() ?? const <BluetoothDevice?>[])
        if (device != null)
          AndroidGattClient(this, device, takeString(device.address)!),
    ];
  }

  @override
  Future<List<PeripheralBackend>> bondedPeripherals() async {
    final devices = guardJni(
      'Listing bonded devices',
      () => adapter.bondedDevices?.asDart() ?? const {},
    );
    return [
      for (final device in devices.nonNulls)
        if (device.type$1 != BluetoothDevice.DEVICE_TYPE_CLASSIC)
          AndroidGattClient(this, device, takeString(device.address)!),
    ];
  }

  @override
  Stream<SystemConnectionEvent> systemConnections(
    List<BluetoothUuid> services,
    List<String> peripheralIds,
  ) => _aclEvents;

  late final Stream<SystemConnectionEvent> _aclEvents = androidBroadcasts(
    _context,
    [
      BluetoothDevice.ACTION_ACL_CONNECTED,
      BluetoothDevice.ACTION_ACL_DISCONNECTED,
    ],
    _aclEvent,
  );

  static final _aclConnected = takeString(BluetoothDevice.ACTION_ACL_CONNECTED);

  static SystemConnectionEvent? _aclEvent(Intent intent) {
    final address = addressExtra(intent);
    if (address == null) return null;
    return SystemConnectionEvent(
      deviceId: address,
      connected: takeString(intent.action) == _aclConnected,
      transport: switch (intent.getIntExtra(
        BluetoothDevice.EXTRA_TRANSPORT,
        BluetoothDevice.TRANSPORT_AUTO,
      )) {
        BluetoothDevice.TRANSPORT_LE => LinkTransport.le,
        BluetoothDevice.TRANSPORT_BREDR => LinkTransport.classic,
        _ => LinkTransport.unknown,
      },
      at: DateTime.now(),
    );
  }

  /// Android does not relaunch apps the way iOS state restoration does;
  /// background delivery covers that instead.
  @override
  Stream<CentralRestoration> get restorations => const Stream.empty();

  /// The scan hit for [result], or null when it names no device.
  ScanHit? hit(ScanResult result) => _hit(result);

  JList<ScanFilter?> nativeFilters(ScanOptions options) => _filters(options);

  ScanSettings scanSettings(ScanOptions options) => _settings(options);

  ScanHit? _hit(ScanResult result) {
    final device = result.device;
    final id = takeString(device?.address);
    if (device == null || id == null) return null;
    final record = result.scanRecord;
    final data = AdvertisementData.parse(
      takeBytes(record?.bytes),
      isConnectable: result.isConnectable,
    );
    record?.release();
    return (
      peripheral: AndroidGattClient(this, device, id),
      rssi: result.rssi,
      data: data,
      native: AndroidHandle(result),
    );
  }

  JList<ScanFilter?> _filters(ScanOptions options) => [
    for (final filter in androidNativeFilters(options))
      androidScanFilter(filter),
  ].toJList();

  ScanSettings _settings(ScanOptions options) {
    if (options.phy == ScanPhy.leCoded && !adapter.isLeCodedPhySupported) {
      throw const UnsupportedFeatureException(
        'leCodedPhy',
        'This device cannot scan on the LE Coded PHY',
      );
    }
    final builder = ScanSettings$Builder()
      ..setScanMode(switch (options.mode) {
        ScanMode.lowPower => ScanSettings.SCAN_MODE_LOW_POWER,
        ScanMode.balanced => ScanSettings.SCAN_MODE_BALANCED,
        ScanMode.lowLatency => ScanSettings.SCAN_MODE_LOW_LATENCY,
      })
      ..setLegacy(options.legacyOnly)
      ..setPhy(switch (options.phy) {
        ScanPhy.all => ScanSettings.PHY_LE_ALL_SUPPORTED,
        ScanPhy.le1M => BluetoothDevice.PHY_LE_1M,
        ScanPhy.leCoded => BluetoothDevice.PHY_LE_CODED,
      });
    final settings = builder.build()!;
    builder.release();
    return settings;
  }

  Future<void> _reserveScanStart() async {
    final now = DateTime.now();
    while (_scanStarts.isNotEmpty &&
        now.difference(_scanStarts.first) > _scanStartWindow) {
      _scanStarts.removeFirst();
    }
    if (_scanStarts.length >= _scanStartLimit) {
      final wait = _scanStartWindow - now.difference(_scanStarts.first);
      BtLog.scan.warning(
        () =>
            'Waiting ${millis(wait)} to start the scan: Android ignores '
            'more than $_scanStartLimit starts in $_scanStartWindow',
      );
      await Future<void>.delayed(wait);
      return _reserveScanStart();
    }
    _scanStarts.add(now);
  }

  void _registerStateReceiver() {
    _stateReceiver = BroadcastReceiver.implement(
      onReceive: (_, intent) {
        final state = intent?.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1);
        intent?.release();
        if (state == null || state < 0) return;
        BtLog.adapter.info(() => 'Adapter ${_state(state).name}');
        _adapterStates.add(_state(state));
      },
    );
    final filter = IntentFilter.new$2(BluetoothAdapter.ACTION_STATE_CHANGED);
    _context.registerReceiver$1(
      _stateReceiver,
      filter,
      Context.RECEIVER_NOT_EXPORTED,
    );
    filter.release();
  }

  void _unregisterStateReceiver() {
    final receiver = _stateReceiver;
    if (receiver == null) return;
    _context.unregisterReceiver(receiver);
    receiver.release();
    _stateReceiver = null;
  }

  static AdapterState _state(int state) => switch (state) {
    BluetoothAdapter.STATE_OFF => AdapterState.poweredOff,
    BluetoothAdapter.STATE_TURNING_ON => AdapterState.turningOn,
    BluetoothAdapter.STATE_ON => AdapterState.poweredOn,
    BluetoothAdapter.STATE_TURNING_OFF => AdapterState.turningOff,
    _ => AdapterState.unknown,
  };
}

/// A native `ScanFilter` for the parts of [filter] Android checks itself.
ScanFilter androidScanFilter(AdvertisementFilter filter) {
  final builder = ScanFilter$Builder();
  if (filter.service case final uuid?) {
    builder.setServiceUuid(_parcelUuid(uuid));
  }
  if (filter.name case final name?) builder.setDeviceName(name.toJString());
  if (filter.peripheralId case final address?) {
    builder.setDeviceAddress(address.toJString());
  }
  if (filter.manufacturerId case final company?) {
    final data = filter.manufacturerData ?? const <int>[];
    builder.setManufacturerData$1(
      company,
      JByteArray.of(data),
      JByteArray.of(_mask(data, filter.manufacturerDataMask)),
    );
  }
  if (filter.serviceData case final uuid?) {
    final data = filter.serviceDataValue ?? const <int>[];
    builder.setServiceData$1(
      _parcelUuid(uuid),
      JByteArray.of(data),
      JByteArray.of(_mask(data, filter.serviceDataMask)),
    );
  }
  final built = builder.build()!;
  builder.release();
  return built;
}

/// Android requires a mask as long as the data; bytes past the given mask
/// must match fully.
List<int> _mask(List<int> data, List<int>? mask) => [
  for (var i = 0; i < data.length; i++)
    mask != null && i < mask.length ? mask[i] : 0xff,
];

ParcelUuid _parcelUuid(BluetoothUuid uuid) =>
    ParcelUuid.fromString(uuid.value.toJString())!;
