import 'dart:async';

import 'package:objective_c/objective_c.dart' as objc;

import '../../central/native_types.dart';
import '../../core/exceptions.dart';
import '../../core/log.dart';
import '../../core/native_handle.dart';
import '../../models/adapter_state.dart';
import '../../models/advertise_options.dart';
import '../../models/bt_kit_options.dart';
import '../../native/ios/bindings.dart';
import '../../peripheral_role/local_gatt.dart';
import '../channel_backend.dart';
import '../peripheral_role_backend.dart';
import 'ios_central.dart';
import 'ios_gatt_server.dart';
import 'ios_streams.dart';
import 'objc_conversions.dart';

/// The peripheral role on iOS. One `CBPeripheralManager` serves the GATT
/// server, advertising and published L2CAP channels, and its delegate
/// routes each callback to the part it concerns.
///
/// iOS runs one GATT server and one advertisement per app.
///
/// With a restore identifier, iOS keeps the services published while the
/// app is not running and hands them back in
/// `peripheralManager:willRestoreState:`. A server that adds a service with
/// the same UUID and characteristics adopts the restored one, so it is not
/// published twice.
final class IosPeripheralRole implements PeripheralRoleBackend {
  IosPeripheralRole(this._options) {
    if (_options.peripheralRestoreIdentifier != null &&
        CBManager.getAuthorization() ==
            CBManagerAuthorization.CBManagerAuthorizationAllowedAlways) {
      manager;
    }
  }

  static const _settleTimeout = Duration(seconds: 3);

  final BtKitOptions _options;
  final _restoredServices = <CBMutableService>[];
  final _restorations = StreamController<PeripheralRoleRestoration>.broadcast();
  PeripheralRoleRestoration? _restored;
  CBPeripheralManager? _manager;
  IosGattServer? _server;
  IosAdvertising? _advertising;
  Completer<IosL2capServer>? _publishing;
  final _l2capServers = <int, IosL2capServer>{};
  final _states = StreamController<AdapterState>.broadcast();

  /// Every callback is a listener, except `willRestoreState`, which runs
  /// synchronously so that the restored services are known before the
  /// first request reaches them.
  late final CBPeripheralManagerDelegate _delegate = () {
    final builder = objc.ObjCProtocolBuilder(debugName: 'BtKitPeripheralRole');
    CBPeripheralManagerDelegate$Builder.addToBuilderAsListener(
      builder,
      peripheralManagerDidUpdateState_: (manager) =>
          _states.add(IosCentral.adapterStateOf(manager.state)),
      peripheralManager_didAddService_error_: (_, _, error) =>
          _server?.didAddService(error),
      peripheralManagerDidStartAdvertising_error_: (_, error) =>
          _advertising?.didStart(error),
      peripheralManager_central_didSubscribeToCharacteristic_:
          (_, central, characteristic) => _server?.didChangeSubscription(
            central,
            characteristic,
            subscribed: true,
          ),
      peripheralManager_central_didUnsubscribeFromCharacteristic_:
          (_, central, characteristic) => _server?.didChangeSubscription(
            central,
            characteristic,
            subscribed: false,
          ),
      peripheralManager_didReceiveReadRequest_: (manager, request) {
        final server = _server;
        if (server != null) return server.didReceiveRead(request);
        manager.respondToRequest(
          request,
          withResult: CBATTError.CBATTErrorAttributeNotFound,
        );
      },
      peripheralManager_didReceiveWriteRequests_: (_, requests) =>
          _server?.didReceiveWrites(requests),
      peripheralManagerIsReadyToUpdateSubscribers_: (_) =>
          _server?.readyToUpdate(),
      peripheralManager_didPublishL2CAPChannel_error_: _didPublish,
      peripheralManager_didOpenL2CAPChannel_error_: (_, channel, error) {
        if (channel == null || error != null) return;
        _l2capServers[channel.PSM]?.accept(channel);
      },
    );
    CBPeripheralManagerDelegate$Builder.peripheralManager_willRestoreState_
        .implementAsBlocking(builder, (_, state) => _restore(state));
    return CBPeripheralManagerDelegate.as(builder.build());
  }();

  CBPeripheralManager get manager =>
      _manager ??= CBPeripheralManager.alloc().initWithDelegate$1(
        _delegate,
        options: <Object, Object>{
          CBPeripheralManagerOptionShowPowerAlertKey: _options.showPowerAlert,
          if (_options.peripheralRestoreIdentifier case final identifier?)
            CBPeripheralManagerOptionRestoreIdentifierKey: identifier
                .toNSString(),
        }.toNSDictionary(),
      );

  @override
  Stream<PeripheralRoleRestoration> get restorations async* {
    if (_restored case final restored?) yield restored;
    yield* _restorations.stream;
  }

  void _restore(objc.NSDictionary state) {
    final values = state.asDart();
    _restoredServices.addAll(
      listOf(
        values[CBPeripheralManagerRestoredStateServicesKey] as objc.NSArray?,
        CBMutableService.as,
      ),
    );
    final restored = _restored = (
      services: [for (final service in _restoredServices) uuidOf(service.UUID)],
      advertising:
          values[CBPeripheralManagerRestoredStateAdvertisementDataKey] != null,
    );
    BtLog.server.info(
      () =>
          'Restored ${restored.services.length} services'
          '${restored.advertising ? ' and advertising' : ''}',
    );
    _restorations.add(restored);
  }

  /// The restored service matching [service], with its characteristics in
  /// the order of [LocalService.characteristics], or null if none matches.
  /// A restored service with the same UUID that does not match is removed.
  (CBMutableService, List<CBMutableCharacteristic>)? takeRestored(
    LocalService service,
  ) {
    final uuid = cbUuid(service.uuid);
    final index = _restoredServices.indexWhere(
      (restored) => restored.UUID.isEqual(uuid),
    );
    if (index < 0) return null;
    final restored = _restoredServices.removeAt(index);
    final available = listOf(
      restored.characteristics,
      CBMutableCharacteristic.as,
    );
    final matched = <CBMutableCharacteristic>[];
    for (final local in service.characteristics) {
      final match = available
          .where((c) => uuidOf(c.UUID) == local.uuid)
          .firstOrNull;
      if (match == null) {
        manager.removeService(restored);
        return null;
      }
      matched.add(match);
    }
    return (restored, matched);
  }

  @override
  Future<AdapterState> settledState() async {
    final state = IosCentral.adapterStateOf(manager.state);
    if (state != AdapterState.unknown && state != AdapterState.resetting) {
      return state;
    }
    return _states.stream
        .firstWhere(
          (s) => s != AdapterState.unknown && s != AdapterState.resetting,
        )
        .timeout(
          _settleTimeout,
          onTimeout: () => IosCentral.adapterStateOf(manager.state),
        );
  }

  @override
  Future<ServerBackend> openServer() async {
    if (_server != null) {
      throw const NativeOperationException(
        'A GATT server is already open; iOS runs one per app',
      );
    }
    return _server = IosGattServer(this);
  }

  void serverClosed(IosGattServer server) {
    if (identical(_server, server)) _server = null;
  }

  @override
  Future<AdvertisingBackend> startAdvertising(AdvertiseOptions options) async {
    _checkAdvertising(options);
    if (_advertising != null) {
      throw const AdvertisingException(
        'Already advertising; iOS runs one advertisement per app',
      );
    }
    final advertising = _advertising = IosAdvertising._(this, options);
    try {
      await advertising._start(options);
    } on Object {
      _advertising = null;
      rethrow;
    }
    return advertising;
  }

  /// iOS advertises a local name and service UUIDs, always connectable,
  /// with the interval and power it chooses.
  static void _checkAdvertising(AdvertiseOptions options) {
    void unsupported(String feature, String message) =>
        throw UnsupportedFeatureException(feature, message);
    if (options.includeDeviceName) {
      unsupported(
        'includeDeviceName',
        'iOS does not advertise the device '
            'name; use localName',
      );
    }
    if (options.manufacturerData.isNotEmpty ||
        options.serviceData.isNotEmpty ||
        options.includeTxPower) {
      unsupported(
        'advertiseCustomData',
        'iOS advertises only a local name '
            'and service UUIDs',
      );
    }
    if (!options.connectable) {
      unsupported(
        'nonConnectableAdvertising',
        'iOS advertisements are '
            'always connectable',
      );
    }
    if (options.periodic != null) {
      unsupported(
        'periodicAdvertising',
        'iOS does not offer periodic advertising',
      );
    }
  }

  @override
  Future<L2capServerBackend> publishL2cap({required bool secure}) {
    if (_publishing != null) {
      throw const NativeOperationException(
        'Another L2CAP channel is being published',
      );
    }
    final publishing = _publishing = Completer();
    manager.publishL2CAPChannelWithEncryption(secure);
    return publishing.future;
  }

  void unpublish(IosL2capServer server) {
    if (_l2capServers.remove(server.psm) != null) {
      manager.unpublishL2CAPChannel(server.psm);
    }
  }

  void _didPublish(CBPeripheralManager _, int psm, objc.NSError? error) {
    final publishing = _publishing;
    _publishing = null;
    if (publishing == null) return;
    if (error != null) {
      return publishing.completeError(errorOf(error, 'publishL2CAPChannel'));
    }
    publishing.complete(_l2capServers[psm] = IosL2capServer(this, psm));
  }
}

/// The advertisement of a `CBPeripheralManager`.
///
/// iOS cannot change a running advertisement, so an update stops it and
/// starts the new one; if that fails, the previous one is started again.
final class IosAdvertising implements AdvertisingBackend {
  IosAdvertising._(this._role, this._options);

  final IosPeripheralRole _role;
  AdvertiseOptions _options;
  Completer<void>? _starting;

  @override
  AdvertisingHandle get native => IosHandle(_role.manager);

  @override
  Future<void> update(AdvertiseOptions options) async {
    IosPeripheralRole._checkAdvertising(options);
    final previous = _options;
    _role.manager.stopAdvertising();
    try {
      await _start(options);
      _options = options;
    } on AdvertisingException {
      _role.manager.stopAdvertising();
      try {
        await _start(previous);
      } on AdvertisingException catch (e) {
        BtLog.server.warning(() => 'Could not advertise again: $e');
      }
      rethrow;
    }
  }

  Future<void> _start(AdvertiseOptions options) {
    final starting = _starting = Completer<void>();
    _role.manager.startAdvertising(
      <Object, Object>{
        CBAdvertisementDataLocalNameKey: ?options.localName,
        if (options.serviceUuids.isNotEmpty)
          CBAdvertisementDataServiceUUIDsKey: [
            for (final uuid in options.serviceUuids) cbUuid(uuid),
          ],
      }.toNSDictionary(),
    );
    return starting.future;
  }

  void didStart(objc.NSError? error) {
    final starting = _starting;
    _starting = null;
    if (starting == null) return;
    if (error == null) return starting.complete();
    starting.completeError(
      AdvertisingException(
        'Advertising failed to start: '
        '${error.localizedDescription.toDartString()}',
        nativeCode: error.code,
        nativeError: error,
      ),
    );
  }

  @override
  Future<void> stop() async {
    _role.manager.stopAdvertising();
    if (identical(_role._advertising, this)) _role._advertising = null;
  }
}
