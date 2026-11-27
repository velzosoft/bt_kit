import '../channels/byte_channel.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../models/capabilities.dart';
import '../native/ios/bindings.dart' as ios;
import '../platform/accessory_backend.dart';

/// MFi accessories connected over Bluetooth Classic or iAP2, through
/// ExternalAccessory (iOS). Reach it through `BtKit.accessories`.
///
/// The app lists each protocol it speaks under
/// `UISupportedExternalAccessoryProtocols` in its `Info.plist`; iOS only
/// reports accessories that speak one of them.
final class ExternalAccessories {
  ExternalAccessories._(this._backend, this._capabilities);

  final AccessoryBackend _backend;
  final BluetoothCapabilities Function() _capabilities;
  final _accessories = <int, ExternalAccessory>{};

  /// The accessories connected now.
  List<ExternalAccessory> get connected {
    if (!_capabilities().externalAccessory) return const [];
    return [for (final item in _backend.connected) _accessory(item)];
  }

  /// Accessories connecting and disconnecting.
  Stream<AccessoryEvent> get changes => _backend.changes.map((change) {
    final accessory = _accessory(change.accessory);
    if (!change.connected) _accessories.remove(accessory.connectionId);
    BtLog.accessory.info(
      () =>
          '${accessory.name} ${change.connected ? 'connected' : 'disconnected'}',
    );
    return AccessoryEvent._(accessory, connected: change.connected);
  });

  /// Shows the system picker for nearby Bluetooth accessories and completes
  /// when the user dismisses it. A chosen accessory pairs and then appears
  /// in [changes].
  Future<void> showBluetoothPicker() async {
    _require();
    await _backend.showBluetoothPicker();
  }

  ExternalAccessory _accessory(AccessoryBackendItem item) =>
      _accessories[item.connectionId] ??= ExternalAccessory._(item);

  void _require() {
    if (!_capabilities().externalAccessory) {
      throw const UnsupportedFeatureException(
        'externalAccessory',
        'ExternalAccessory is an iOS API; on Android use BtKit.classic',
      );
    }
  }
}

/// One connected MFi accessory (iOS).
final class ExternalAccessory {
  ExternalAccessory._(this._backend);

  final AccessoryBackendItem _backend;

  /// Identifies this connection; a reconnected accessory gets a new one.
  int get connectionId => _backend.connectionId;

  String get name => _backend.name;
  String get manufacturer => _backend.manufacturer;
  String get modelNumber => _backend.modelNumber;
  String get serialNumber => _backend.serialNumber;
  String get firmwareRevision => _backend.firmwareRevision;
  String get hardwareRevision => _backend.hardwareRevision;

  /// The protocols the accessory speaks, such as `com.example.sensor`.
  List<String> get protocols => _backend.protocols;

  bool get isConnected => _backend.isConnected;

  ios.EAAccessory get native => _backend.native;

  /// Opens a session for [protocol], one of [protocols] that the app also
  /// lists in its `Info.plist`. iOS allows one session per protocol at a
  /// time.
  Future<AccessorySession> openSession(String protocol) async {
    if (!isConnected) {
      throw const DisconnectedException('The accessory is not connected');
    }
    if (!protocols.contains(protocol)) {
      throw ArgumentError.value(
        protocol,
        'protocol',
        'Not one of the protocols $name speaks: ${protocols.join(', ')}',
      );
    }
    final session = await _backend.openSession(protocol);
    return createAccessorySession(session, this, protocol);
  }

  @override
  String toString() => 'ExternalAccessory($name, $connectionId)';
}

/// An accessory connected or disconnected.
final class AccessoryEvent {
  AccessoryEvent._(this.accessory, {required this.connected});

  final ExternalAccessory accessory;
  final bool connected;

  @override
  String toString() =>
      'AccessoryEvent(${accessory.name}, '
      '${connected ? 'connected' : 'disconnected'})';
}

ExternalAccessories createExternalAccessories(
  AccessoryBackend backend,
  BluetoothCapabilities Function() capabilities,
) => ExternalAccessories._(backend, capabilities);
