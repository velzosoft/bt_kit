import 'dart:io';
import 'dart:typed_data';

import '../central/native_types.dart';
import '../core/bluetooth_uuid.dart';
import '../models/adapter_state.dart';
import '../models/advertisement_data.dart';
import '../models/bt_kit_options.dart';
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
import 'accessory_backend.dart';
import 'android/android_central.dart';
import 'audio_backend.dart';
import 'background_backend.dart';
import 'bond_backend.dart';
import 'channel_backend.dart';
import 'classic_backend.dart';
import 'companion_backend.dart';
import 'ios/ios_central.dart';
import 'peripheral_role_backend.dart';

/// The central role of one platform, implemented on top of Layer 1.
abstract interface class CentralBackend {
  factory CentralBackend([BtKitOptions options = const BtKitOptions()]) {
    if (Platform.isAndroid) return AndroidCentral();
    if (Platform.isIOS) return IosCentral(options);
    throw UnsupportedError('bt_kit supports Android and iOS only');
  }

  AdapterHandle get native;
  BluetoothCapabilities get capabilities;

  /// The local device in the peripheral role.
  PeripheralRoleBackend get peripheralRole;

  ClassicBackend get classic;
  AccessoryBackend get accessories;
  CompanionBackend get companion;
  BackgroundBackend get background;
  AudioBackend get audio;
  AdapterState get adapterState;
  Stream<AdapterState> get adapterStates;

  Future<Map<BluetoothPermission, PermissionStatus>> checkPermissions(
    Set<BluetoothPermission> permissions,
  );

  Future<Map<BluetoothPermission, PermissionStatus>> requestPermissions(
    Set<BluetoothPermission> permissions,
  );

  /// The permissions a scan needs: Android adds location when the app's
  /// manifest does not disavow it.
  Set<BluetoothPermission> get scanPermissions;

  /// The name the adapter shows to other devices.
  Future<String?> adapterName();

  /// Waits until the adapter leaves the transient states it reports right
  /// after start-up.
  Future<AdapterState> settledAdapterState();

  Future<bool> requestEnable();

  /// Starts a native scan on listen and stops it on cancel. Only one scan
  /// runs at a time.
  ///
  /// Applies as much of the options' filters natively as the platform can;
  /// the caller checks every filter again and removes duplicates.
  Stream<ScanHit> scan(ScanOptions options);

  Future<PeripheralBackend?> peripheral(String id);

  /// Peripherals connected to this device by any app.
  Future<List<PeripheralBackend>> systemPeripherals(
    List<BluetoothUuid> services,
  );

  /// LE devices this device is bonded with.
  Future<List<PeripheralBackend>> bondedPeripherals();

  /// Shows the system Bluetooth settings; completes when the user returns.
  Future<void> openBluetoothSettings();

  /// Connections any app makes; reported while listened. iOS reports only
  /// peripherals matching [services] or [peripheralIds].
  Stream<SystemConnectionEvent> systemConnections(
    List<BluetoothUuid> services,
    List<String> peripheralIds,
  );

  /// What iOS restored when it relaunched the app (state restoration). The
  /// last restoration is replayed to each new listener.
  Stream<CentralRestoration> get restorations;
}

typedef CentralRestoration = ({
  List<PeripheralBackend> peripherals,
  List<BluetoothUuid> scanServices,
});

/// A GATT client for one remote peripheral.
///
/// Each method issues exactly one platform request; the caller serializes
/// them. Pending requests fail with `DisconnectedException` when the link
/// drops.
abstract interface class PeripheralBackend {
  String get id;
  String? get name;
  PeripheralHandle get native;

  BluetoothConnectionState get connectionState;
  Stream<BluetoothConnectionState> get connectionStates;

  /// Why the link last went down; set before [connectionStates] reports
  /// [BluetoothConnectionState.disconnected].
  DisconnectReason? get lastDisconnect;

  BondBackend get bond;

  /// Values pushed by the peripheral, keyed by [DiscoveredCharacteristic.key].
  Stream<ValueNotification> get notifications;

  /// Changes to the link the peripheral or the platform made.
  Stream<LinkUpdate> get updates;

  /// The ATT MTU in effect.
  int get mtu;

  /// Waits for a disconnection still in progress first, so that its grace
  /// period can never close the new connection.
  Future<void> connect({required bool autoConnect});

  /// Completes once the link is down, or after a grace period if the
  /// platform never reports it; concurrent calls share one disconnection.
  /// A [connect] still waiting to start fails with
  /// `OperationCancelledException`.
  Future<void> disconnect();
  Future<List<DiscoveredService>> discoverServices();
  Future<Uint8List> readCharacteristic(DiscoveredCharacteristic characteristic);

  Future<void> writeCharacteristic(
    DiscoveredCharacteristic characteristic,
    Uint8List value, {
    required bool withResponse,
  });

  /// Turns pushes on in [mode], which is never [NotifyMode.auto], or off
  /// when [mode] is null.
  Future<void> setNotifying(
    DiscoveredCharacteristic characteristic,
    NotifyMode? mode,
  );

  Future<Uint8List> readDescriptor(DiscoveredDescriptor descriptor);

  Future<void> writeDescriptor(
    DiscoveredDescriptor descriptor,
    Uint8List value,
  );

  Future<int> readRssi();

  /// Requests [mtu] and returns the MTU in effect afterwards.
  Future<int> requestMtu(int mtu);

  int maximumWriteLength({required bool withResponse});

  /// Completes once the platform accepted the request.
  Future<void> requestConnectionPriority(ConnectionPriority priority);

  /// Completes with the PHYs in effect after the update.
  Future<PhyInfo> setPreferredPhy(Set<Phy> tx, Set<Phy> rx, PhyCoding coding);

  Future<PhyInfo> readPhy();

  /// Clears the platform's cache of the peripheral's GATT database; returns
  /// whether the platform accepted.
  Future<bool> clearGattCache();

  /// Opens an L2CAP channel to [psm] on this connected peripheral.
  Future<L2capChannelBackend> openL2capChannel(int psm, {required bool secure});

  /// Measures the distance to the peripheral from listen until cancel.
  Stream<DistanceMeasurement> measureDistance(
    DistanceMethod method,
    MeasurementRate rate,
  );
}

typedef ScanHit = ({
  PeripheralBackend peripheral,
  int rssi,
  AdvertisementData data,
  AdvertisementHandle? native,
});

typedef ValueNotification = ({Object key, Uint8List value});

sealed class LinkUpdate {
  const LinkUpdate();
}

final class MtuUpdate extends LinkUpdate {
  const MtuUpdate(this.mtu);

  final int mtu;
}

final class PhyUpdate extends LinkUpdate {
  const PhyUpdate(this.phy);

  final PhyInfo phy;
}

/// The peripheral changed its GATT database.
final class ServicesUpdate extends LinkUpdate {
  const ServicesUpdate([this.invalidated]);

  /// The [DiscoveredService.key]s of the services that are no longer
  /// valid, or null when every service is.
  final List<Object>? invalidated;
}

final class NameUpdate extends LinkUpdate {
  const NameUpdate(this.name);

  final String? name;
}

final class DiscoveredService {
  const DiscoveredService(
    this.uuid,
    this.isPrimary,
    this.key,
    this.characteristics,
    this.native, {
    this.included = const [],
  });

  final BluetoothUuid uuid;
  final bool isPrimary;

  /// Identifies the service in [ServicesUpdate].
  final Object key;
  final List<DiscoveredCharacteristic> characteristics;

  /// The keys of the services this one includes, each of which is in the
  /// same discovery.
  final List<Object> included;

  /// Null for fakes.
  final ServiceHandle? native;
}

final class DiscoveredCharacteristic {
  const DiscoveredCharacteristic(
    this.uuid,
    this.properties,
    this.key,
    this.descriptors,
    this.native,
  );

  final BluetoothUuid uuid;
  final int properties;

  /// Identifies the characteristic in [PeripheralBackend.notifications].
  final Object key;
  final List<DiscoveredDescriptor> descriptors;

  /// Null for fakes.
  final CharacteristicHandle? native;
}

final class DiscoveredDescriptor {
  const DiscoveredDescriptor(this.uuid, this.key, this.native);

  final BluetoothUuid uuid;
  final Object key;

  /// Null for fakes.
  final DescriptorHandle? native;
}
