import '../central/native_types.dart';
import '../central/peripheral.dart';
import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../models/capabilities.dart';
import '../models/companion_request.dart';
import '../platform/companion_backend.dart';

/// Devices the user paired with this app through the system companion
/// picker: `CompanionDeviceManager` associations on Android,
/// AccessorySetupKit accessories on iOS. Reach it through `BtKit.companion`.
///
/// The picker needs no Bluetooth permission: the user's choice grants the
/// app that one device. On Android an association also lets the app remove
/// the device's bond and observe its presence in the background.
final class CompanionDevices {
  CompanionDevices._(this._backend, this._capabilities, this._peripheral);

  final CompanionBackend _backend;
  final BluetoothCapabilities Function() _capabilities;
  final Future<Peripheral?> Function(String id) _peripheral;

  /// Shows the system picker and returns the device the user chose, or null
  /// when they dismissed it.
  ///
  /// The picker waits for the user, so there is no timeout; cancelling
  /// [cancelToken] stops waiting for the answer.
  Future<CompanionDevice?> associate(
    CompanionRequest request, {
    CancelToken? cancelToken,
  }) async {
    _require();
    final associating = _backend.associate(request);
    final backend = cancelToken == null
        ? await associating
        : await Future.any([
            associating,
            cancelToken.whenCancelled.then<CompanionDeviceBackend?>(
              (reason) => throw OperationCancelledException(reason),
            ),
          ]);
    if (backend == null) return null;
    BtLog.accessory.info(() => 'Associated ${backend.name ?? backend.id}');
    return _device(backend);
  }

  /// The devices associated with this app.
  Future<List<CompanionDevice>> devices() async {
    if (!_capabilities().companionDevices) return const [];
    return [for (final backend in await _backend.devices()) _device(backend)];
  }

  /// Ends the association. On Android this also stops presence events; it
  /// does not remove the bond.
  Future<void> remove(CompanionDevice device) async {
    _require();
    await _backend.remove(device._backend);
    BtLog.accessory.info(() => 'Removed ${device.name ?? device.id}');
  }

  /// Devices added, removed or renamed outside this app's calls, such as in
  /// the Settings app (iOS).
  Stream<CompanionDeviceChange> get changes => _backend.changes.map(
    (change) => CompanionDeviceChange._(_device(change.device), change.kind),
  );

  /// Starts presence events for [device]: `CompanionPresenceChanged`
  /// arrives through `BtKit.backgroundEvents`, or the handler registered
  /// with `BtKit.registerBackgroundHandler` while the app is not running
  /// (Android).
  ///
  /// The app declares `dev.btkit.CompanionPresenceService` in its manifest.
  Future<void> startObservingPresence(CompanionDevice device) =>
      _observe(device, observe: true);

  Future<void> stopObservingPresence(CompanionDevice device) =>
      _observe(device, observe: false);

  Future<void> _observe(CompanionDevice device, {required bool observe}) async {
    if (!_capabilities().backgroundEvents) {
      throw const UnsupportedFeatureException(
        'companionPresence',
        'Presence events need Android; iOS reports accessories through '
            'state restoration instead',
      );
    }
    return _backend.observePresence(device._backend, observe: observe);
  }

  CompanionDevice _device(CompanionDeviceBackend backend) =>
      CompanionDevice._(backend, _peripheral);

  void _require() {
    if (!_capabilities().companionDevices) {
      throw const UnsupportedFeatureException(
        'companionDevices',
        'The companion device picker needs Android or iOS 18',
      );
    }
  }
}

/// A device associated with this app through the companion picker.
final class CompanionDevice {
  CompanionDevice._(this._backend, this._peripheral);

  final CompanionDeviceBackend _backend;
  final Future<Peripheral?> Function(String id) _peripheral;

  /// Android: the association id. iOS: the accessory's Bluetooth
  /// identifier.
  String get id => _backend.id;

  String? get name => _backend.name;

  /// The id `BtKit.peripheral` takes: a MAC address on Android, a UUID on
  /// iOS.
  String? get peripheralId => _backend.peripheralId;

  /// `AssociationInfo` on Android, `ASAccessory` on iOS.
  CompanionHandle get native => _backend.native;

  /// The peripheral behind the device, ready to connect.
  Future<Peripheral?> peripheral() async {
    final id = peripheralId;
    return id == null ? null : _peripheral(id);
  }

  @override
  bool operator ==(Object other) => other is CompanionDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'CompanionDevice($id, ${name ?? '-'})';
}

/// A companion device that changed outside this app's calls (iOS).
final class CompanionDeviceChange {
  CompanionDeviceChange._(this.device, this.kind);

  final CompanionDevice device;
  final CompanionChangeKind kind;

  @override
  String toString() => 'CompanionDeviceChange(${device.id}, ${kind.name})';
}

CompanionDevices createCompanionDevices(
  CompanionBackend backend,
  BluetoothCapabilities Function() capabilities,
  Future<Peripheral?> Function(String id) peripheral,
) => CompanionDevices._(backend, capabilities, peripheral);
