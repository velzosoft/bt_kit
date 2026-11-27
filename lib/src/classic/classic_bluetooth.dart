import 'dart:async';

import '../central/bonding.dart';
import '../central/device_host.dart';
import '../central/peripheral.dart';
import '../channels/byte_channel.dart';
import '../core/bluetooth_uuid.dart';
import '../core/cancel_token.dart';
import '../core/exceptions.dart';
import '../core/log.dart';
import '../core/operation_queue.dart';
import '../models/bond_state.dart';
import '../models/device_class.dart';
import '../models/permission.dart';
import '../native/android/bindings.dart' as android;
import '../platform/channel_backend.dart';
import '../platform/classic_backend.dart';

/// Bluetooth Classic (BR/EDR) devices: discovery, bonding and RFCOMM
/// sockets (Android). Reach it through `BtKit.classic`.
///
/// iOS reaches Classic devices only as MFi accessories, through
/// `BtKit.accessories`.
final class ClassicBluetooth {
  ClassicBluetooth._(this._backend, this._host);

  final ClassicBackend _backend;
  final DeviceHost _host;
  final _devices = <String, WeakReference<ClassicDevice>>{};
  var _discovering = false;

  /// Whether a [discover] stream is running.
  bool get isDiscovering => _discovering;

  /// Runs one inquiry, about 12 seconds, reporting each device as it is
  /// found; the stream ends with the inquiry. Cancel to stop early.
  ///
  /// One discovery runs at a time; another fails with [ScanException].
  /// Discovery slows down every other link, so stop it before connecting.
  Stream<DiscoveredDevice> discover() {
    late final StreamController<DiscoveredDevice> controller;
    StreamSubscription<ClassicHit>? hits;
    void finish() {
      if (hits != null) _discovering = false;
      hits = null;
    }

    controller = StreamController<DiscoveredDevice>(
      onListen: () async {
        try {
          _requireClassic();
          await _host.ensureReady(const {BluetoothPermission.scan});
          if (!controller.hasListener) return;
          if (_discovering) {
            throw const ScanException('A Classic discovery is already running');
          }
          _discovering = true;
          BtLog.classic.info(() => 'Discovery started');
          hits = _backend.discover().listen(
            (hit) => controller.add(
              DiscoveredDevice._(
                _device(hit.device),
                name: hit.name,
                rssi: hit.rssi,
                deviceClass: hit.deviceClass,
                receivedAt: DateTime.now(),
              ),
            ),
            onError: controller.addError,
            onDone: () {
              BtLog.classic.info(() => 'Discovery finished');
              finish();
              unawaited(controller.close());
            },
          );
        } on BluetoothException catch (e) {
          controller.addError(e);
          await controller.close();
        }
      },
      onCancel: () {
        final active = hits;
        finish();
        return active?.cancel();
      },
    );
    return controller.stream;
  }

  /// The device with the MAC address [id], or null if [id] is not one.
  Future<ClassicDevice?> device(String id) async {
    _requireClassic();
    final backend = await _backend.device(id);
    return backend == null ? null : _device(backend);
  }

  /// The Classic and dual-mode devices this device is bonded with.
  Future<List<ClassicDevice>> bondedDevices() async {
    _requireClassic();
    await _host.ensureReady(const {BluetoothPermission.connect});
    return [
      for (final backend in await _backend.bondedDevices()) _device(backend),
    ];
  }

  /// Publishes an RFCOMM service and accepts connections to it.
  ///
  /// [name] and [service] go into the SDP record remote devices look up.
  /// With [secure], connections must be authenticated and encrypted.
  Future<RfcommServer> listen({
    required BluetoothUuid service,
    required String name,
    bool secure = true,
  }) async {
    _requireClassic();
    await _host.ensureReady(const {BluetoothPermission.connect});
    final server = await _backend.listen(name, service, secure: secure);
    BtLog.classic.info(() => 'Listening for RFCOMM $service');
    return createRfcommServer(server, service);
  }

  ClassicDevice _device(ClassicDeviceBackend backend) {
    final cached = _devices[backend.id]?.target;
    if (cached != null) return cached;
    if (_devices.length > 256) {
      _devices.removeWhere((_, ref) => ref.target == null);
    }
    final created = ClassicDevice._(backend, _host);
    _devices[backend.id] = WeakReference(created);
    return created;
  }

  void _requireClassic() {
    if (!_host.capabilities.classic) {
      throw const UnsupportedFeatureException(
        'classic',
        'This platform offers no Bluetooth Classic API; on iOS use '
            'ExternalAccessory through BtKit.accessories',
      );
    }
  }
}

/// A remote Bluetooth Classic or dual-mode device (Android).
///
/// Bonding and connections are queued per device, have a timeout and take a
/// [CancelToken].
final class ClassicDevice {
  ClassicDevice._(this._backend, this._host);

  final ClassicDeviceBackend _backend;
  final DeviceHost _host;
  late final _queue = OperationQueue(log: BtLog.classic, label: id);
  late final _bonding = Bonding(_backend.bond, _host, _queue, id);

  /// The MAC address.
  String get id => _backend.id;

  String? get name => _backend.name;

  DeviceClass? get deviceClass => _backend.deviceClass;

  android.BluetoothDevice get native => _backend.native;

  BondState get bondState => _bonding.state;

  Stream<BondState> get bondStates => _bonding.states;

  /// Pairs with the device and completes once it is bonded.
  ///
  /// Android may show a pairing dialog, so the default [timeout] is long.
  /// Pairing that ends without a bond fails with [BondException].
  Future<void> createBond({
    Duration timeout = Timeouts.bond,
    CancelToken? cancelToken,
  }) => _bonding.create(timeout: timeout, cancelToken: cancelToken);

  /// Removes the bond and returns whether it is gone; see
  /// `Peripheral.removeBond`.
  Future<bool> removeBond({
    Duration timeout = Timeouts.bond,
    CancelToken? cancelToken,
  }) => _bonding.remove(timeout: timeout, cancelToken: cancelToken);

  /// Opens an RFCOMM socket to [service], which the device publishes in its
  /// SDP records. The Serial Port Profile is [BluetoothUuid.serialPort].
  ///
  /// With [secure], the link is authenticated and encrypted, which pairs
  /// the devices first if they are not bonded.
  Future<RfcommChannel> connect(
    BluetoothUuid service, {
    bool secure = true,
    Duration timeout = Timeouts.connect,
    CancelToken? cancelToken,
  }) async {
    await _host.ensureReady(const {BluetoothPermission.connect});
    Future<RfcommChannelBackend>? opening;
    try {
      final channel = await _queue.run(
        'connect RFCOMM $service',
        () => opening = _backend.connect(service, secure: secure),
        timeout: timeout,
        cancelToken: cancelToken,
      );
      return createRfcommChannel(channel, service);
    } on BluetoothException catch (e) {
      if (e is OperationTimeoutException || e is OperationCancelledException) {
        unawaited(
          opening?.then((channel) => channel.close(), onError: (Object _) {}),
        );
      }
      rethrow;
    }
  }

  @override
  String toString() => 'ClassicDevice($id)';
}

/// A device found by [ClassicBluetooth.discover].
final class DiscoveredDevice {
  DiscoveredDevice._(
    this.device, {
    required this.name,
    required this.rssi,
    required this.deviceClass,
    required this.receivedAt,
  });

  final ClassicDevice device;

  /// The name the inquiry reported, when the device sent one.
  final String? name;

  /// Signal strength in dBm.
  final int? rssi;
  final DeviceClass? deviceClass;
  final DateTime receivedAt;

  @override
  String toString() => 'DiscoveredDevice(${device.id}, ${name ?? '-'})';
}

ClassicBluetooth createClassicBluetooth(
  ClassicBackend backend,
  DeviceHost host,
) => ClassicBluetooth._(backend, host);
