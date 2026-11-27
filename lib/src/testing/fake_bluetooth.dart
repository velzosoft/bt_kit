import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../central/bt_kit.dart';
import '../central/native_types.dart';
import '../core/bluetooth_uuid.dart';
import '../core/exceptions.dart';
import '../models/adapter_state.dart';
import '../models/advertise_options.dart';
import '../models/advertisement_data.dart';
import '../models/bond_state.dart';
import '../models/capabilities.dart';
import '../models/connection_priority.dart';
import '../models/bluetooth_connection_state.dart';
import '../models/disconnect_reason.dart';
import '../models/distance.dart';
import '../models/notify_mode.dart';
import '../models/permission.dart';
import '../models/phy.dart';
import '../models/scan_options.dart';
import '../models/system_connection.dart';
import '../peripheral_role/gatt_server.dart';
import '../peripheral_role/local_gatt.dart';
import '../platform/accessory_backend.dart';
import '../platform/audio_backend.dart';
import '../platform/background_backend.dart';
import '../platform/bond_backend.dart';
import '../platform/central_backend.dart';
import '../platform/channel_backend.dart';
import '../platform/classic_backend.dart';
import '../platform/companion_backend.dart';
import '../platform/peripheral_role_backend.dart';
import '../platform/unsupported.dart';

part 'fake_central.dart';
part 'fake_link.dart';
part 'fake_peripheral.dart';

/// A simulated Bluetooth stack for app tests, installed as `BtKit.instance`.
///
/// Peripherals are [FakePeripheral]s, served from the same [LocalService]
/// models a real `GattServer` uses. Requests go through the real Layer 2
/// queues, timeouts and errors.
///
/// ```dart
/// late FakeBluetooth bluetooth;
///
/// setUp(() => bluetooth = FakeBluetooth.install());
/// tearDown(FakeBluetooth.uninstall);
///
/// test('reads the battery level', () async {
///   bluetooth.add(FakePeripheral(id: 'AA:BB:CC:DD:EE:FF', services: [battery]));
///   ...
/// });
/// ```
///
/// Bonding, GATT cache refresh and the adapter name are simulated on
/// [androidCapabilities]. The peripheral role,
/// L2CAP, Bluetooth Classic, accessories, companion devices, background
/// delivery, restoration, ranging and audio state are not: both capability
/// sets report them as unsupported.
final class FakeBluetooth {
  FakeBluetooth._(this.capabilities);

  /// Replaces `BtKit.instance` with a new, powered-on fake.
  ///
  /// Call it before the code under test first reads `BtKit.instance`, and
  /// [uninstall] when the test ends.
  static FakeBluetooth install({
    BluetoothCapabilities capabilities = androidCapabilities,
  }) {
    final bluetooth = FakeBluetooth._(capabilities);
    installBackend(_FakeCentral(bluetooth));
    return bluetooth;
  }

  /// Restores the platform's `BtKit.instance`.
  static void uninstall() => installBackend(null);

  /// What an Android phone reports, minus what is not simulated.
  static const androidCapabilities = BluetoothCapabilities(
    lowEnergy: true,
    classic: true,
    le2MPhy: true,
    leCodedPhy: true,
    extendedAdvertising: true,
    periodicAdvertising: false,
    channelSounding: false,
    requestMtu: true,
    connectionPriority: true,
    phy: true,
    notifyMode: true,
    requestEnable: true,
    peripheralRole: false,
    advertiseLocalName: false,
    advertiseCustomData: false,
    l2cap: false,
    bonding: true,
    removeBond: true,
    externalAccessory: false,
    companionDevices: false,
    backgroundEvents: false,
    stateRestoration: false,
    systemConnectionEvents: false,
    rssiRanging: false,
    audioProfiles: false,
    gattCacheRefresh: true,
    adapterName: true,
    serverConnectionPriority: false,
  );

  /// What an iPhone reports, minus what is not simulated.
  static const iosCapabilities = BluetoothCapabilities(
    lowEnergy: true,
    classic: false,
    le2MPhy: false,
    leCodedPhy: false,
    extendedAdvertising: true,
    periodicAdvertising: false,
    channelSounding: false,
    requestMtu: false,
    connectionPriority: false,
    phy: false,
    notifyMode: false,
    requestEnable: false,
    peripheralRole: false,
    advertiseLocalName: false,
    advertiseCustomData: false,
    l2cap: false,
    bonding: false,
    removeBond: false,
    externalAccessory: false,
    companionDevices: false,
    backgroundEvents: false,
    stateRestoration: false,
    systemConnectionEvents: false,
    rssiRanging: false,
    audioProfiles: false,
    gattCacheRefresh: false,
    adapterName: false,
    serverConnectionPriority: false,
  );

  BluetoothCapabilities capabilities;

  /// What `BtKit.adapterName` reports.
  String? adapterName = 'FakeBluetooth';

  /// The status of each permission; all granted at first.
  final permissions = {
    for (final permission in BluetoothPermission.values)
      permission: PermissionStatus.granted,
  };

  /// What a permission request turns `notDetermined` and `denied`
  /// permissions into: the user's answer.
  PermissionStatus requestAnswer = PermissionStatus.granted;

  /// How many times the app opened the Bluetooth settings, which it does to
  /// remove a bond where `capabilities.removeBond` is false.
  int settingsOpened = 0;

  final _peripherals = <String, FakePeripheral>{};
  final _states = StreamController<AdapterState>.broadcast();
  final _scans = <StreamController<ScanHit>>{};
  final _script = Queue<Object>();
  var _adapterState = AdapterState.poweredOn;

  AdapterState get adapterState => _adapterState;

  /// Changes the adapter state. Leaving `poweredOn` drops every connection
  /// with [DisconnectCause.adapterOff] and silences running scans.
  set adapterState(AdapterState state) {
    if (state == _adapterState) return;
    _adapterState = state;
    if (!state.isPoweredOn) {
      for (final peripheral in _peripherals.values) {
        peripheral._link._drop(DisconnectCause.adapterOff);
      }
    }
    _states.add(state);
  }

  List<FakePeripheral> get peripherals =>
      List.unmodifiable(_peripherals.values);

  /// Adds [peripheral]; running scans see it at once if it is in range.
  void add(FakePeripheral peripheral) {
    if (peripheral._bluetooth != null) {
      throw StateError('${peripheral.id} was already added');
    }
    peripheral._bluetooth = this;
    _peripherals[peripheral.id] = peripheral;
    peripheral.advertise();
  }

  /// Removes [peripheral], dropping its connection with
  /// [DisconnectCause.linkLoss].
  void remove(FakePeripheral peripheral) {
    if (_peripherals.remove(peripheral.id) == null) return;
    peripheral._link._drop(DisconnectCause.linkLoss);
    peripheral._bluetooth = null;
  }

  /// The next GATT request to any peripheral fails with [error].
  void failNext(GattError error) => _script.add(error);

  /// The next GATT request to any peripheral is never answered. Its caller
  /// times out, and the peripheral stays busy until the link drops, as a
  /// real one would.
  void timeoutNext() => _script.add(const _Unanswered());

  Object? _nextScripted() => _script.isEmpty ? null : _script.removeFirst();

  void _advertised(FakePeripheral peripheral) {
    for (final scan in _scans.toList()) {
      _deliver(scan, peripheral);
    }
  }

  void _deliver(StreamController<ScanHit> scan, FakePeripheral peripheral) {
    if (!_adapterState.isPoweredOn || !peripheral.inRange) return;
    scan.add((
      peripheral: peripheral._link,
      rssi: peripheral.rssi,
      data: peripheral.advertisement,
      native: null,
    ));
  }
}

final class _Unanswered {
  const _Unanswered();
}

Never _noNative() =>
    throw UnsupportedError('Fake Bluetooth objects have no native object');
