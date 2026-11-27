import 'dart:async';

import 'package:jni/jni.dart';

import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../models/device_class.dart';
import '../../native/android/bindings.dart';
import '../bond_backend.dart';
import '../channel_backend.dart';
import '../classic_backend.dart';
import 'android_bonds.dart';
import 'android_broadcasts.dart';
import 'android_central.dart';
import 'android_sockets.dart';
import 'jni_conversions.dart';

/// Bluetooth Classic on `BluetoothAdapter`: inquiry through
/// `startDiscovery` and its broadcasts, and RFCOMM sockets.
///
/// Platform quirks handled here:
/// * Results and the end of an inquiry arrive only as broadcasts.
/// * `ACTION_DISCOVERY_FINISHED` from an inquiry already running can arrive
///   right after a new one starts; only the end of an inquiry seen starting
///   counts.
/// * An RFCOMM connect during an inquiry is slow and often fails, so the
///   inquiry is cancelled first.
final class AndroidClassic implements ClassicBackend {
  AndroidClassic(this._central);

  final AndroidCentral _central;

  @override
  Stream<ClassicHit> discover() {
    late final StreamController<ClassicHit> controller;
    StreamSubscription<_Discovery>? events;
    var started = false;
    controller = StreamController<ClassicHit>(
      onListen: () {
        events =
            androidBroadcasts(_central.context, [
              BluetoothAdapter.ACTION_DISCOVERY_STARTED,
              BluetoothDevice.ACTION_FOUND,
              BluetoothAdapter.ACTION_DISCOVERY_FINISHED,
            ], _parse).listen((event) {
              switch (event) {
                case _Started():
                  started = true;
                case _Found(:final hit):
                  controller.add(hit);
                case _Finished() when started:
                  unawaited(controller.close());
                case _Finished():
              }
            });
        try {
          final accepted = guardJni(
            'Starting discovery',
            _central.adapter.startDiscovery,
          );
          if (!accepted) {
            throw const ScanException('Android refused to start discovery');
          }
        } on BluetoothException catch (e) {
          controller.addError(e);
          unawaited(controller.close());
        }
      },
      onCancel: () async {
        await events?.cancel();
        guardJni('Cancelling discovery', _central.adapter.cancelDiscovery);
      },
    );
    return controller.stream;
  }

  @override
  Future<ClassicDeviceBackend?> device(String id) async {
    final address = id.toUpperCase();
    if (!BluetoothAdapter.checkBluetoothAddress(address.toJString())) {
      return null;
    }
    final device = _central.adapter.getRemoteDevice$1(address.toJString());
    return device == null ? null : AndroidClassicDevice(_central, device);
  }

  @override
  Future<List<ClassicDeviceBackend>> bondedDevices() async {
    final devices = guardJni(
      'Listing bonded devices',
      () => _central.adapter.bondedDevices?.asDart() ?? const {},
    );
    return [
      for (final device in devices.nonNulls)
        if (device.type$1 != BluetoothDevice.DEVICE_TYPE_LE)
          AndroidClassicDevice(_central, device),
    ];
  }

  @override
  Future<RfcommServerBackend> listen(
    String name,
    BluetoothUuid service, {
    required bool secure,
  }) async {
    final adapter = _central.adapter;
    final socket = guardJni(
      'Listening for RFCOMM connections',
      () => secure
          ? adapter.listenUsingRfcommWithServiceRecord(
              name.toJString(),
              javaUuid(service),
            )
          : adapter.listenUsingInsecureRfcommWithServiceRecord(
              name.toJString(),
              javaUuid(service),
            ),
    );
    if (socket == null) {
      throw const NativeOperationException(
        'Android did not create an RFCOMM server socket',
      );
    }
    return AndroidRfcommServer(socket);
  }

  _Discovery? _parse(Intent intent) {
    final action = takeString(intent.action);
    if (action == _startedAction) return const _Started();
    if (action == _finishedAction) return const _Finished();
    final device = deviceExtra(intent);
    if (device == null) return null;
    final rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, _noRssi);
    final deviceClass = intent.getParcelableExtra<BluetoothClass?>(
      BluetoothDevice.EXTRA_CLASS,
      _classClass,
    );
    return _Found((
      device: AndroidClassicDevice(_central, device),
      name: takeString(intent.getStringExtra(BluetoothDevice.EXTRA_NAME)),
      rssi: rssi == _noRssi ? null : rssi,
      deviceClass: deviceClassOf(deviceClass),
    ));
  }

  static const _noRssi = -32768;
  static final _startedAction = takeString(
    BluetoothAdapter.ACTION_DISCOVERY_STARTED,
  );
  static final _finishedAction = takeString(
    BluetoothAdapter.ACTION_DISCOVERY_FINISHED,
  );
  static final _classClass = BluetoothClass.type.jClass;
}

/// `BluetoothClass` hides the full Class of Device; its `toString` prints
/// it in hexadecimal.
DeviceClass? deviceClassOf(BluetoothClass? bluetoothClass) {
  if (bluetoothClass == null) return null;
  final hex = takeString(bluetoothClass.toString$1());
  bluetoothClass.release();
  final value = hex == null ? null : int.tryParse(hex, radix: 16);
  return value == null ? null : DeviceClass(value);
}

sealed class _Discovery {
  const _Discovery();
}

final class _Started extends _Discovery {
  const _Started();
}

final class _Found extends _Discovery {
  const _Found(this.hit);

  final ClassicHit hit;
}

final class _Finished extends _Discovery {
  const _Finished();
}

/// A remote device as Bluetooth Classic sees it.
final class AndroidClassicDevice implements ClassicDeviceBackend {
  AndroidClassicDevice(this._central, this.native)
    : id = takeString(native.address) ?? '';

  final AndroidCentral _central;

  @override
  final BluetoothDevice native;

  @override
  final String id;

  @override
  String? get name =>
      guardJni('Reading the device name', () => takeString(native.name));

  @override
  DeviceClass? get deviceClass => guardJni(
    'Reading the device class',
    () => deviceClassOf(native.bluetoothClass),
  );

  @override
  late final BondBackend bond = AndroidBond(
    _central.bonds,
    _central.companion,
    native,
    id,
  );

  @override
  Future<RfcommChannelBackend> connect(
    BluetoothUuid service, {
    required bool secure,
  }) async {
    guardJni('Cancelling discovery', _central.adapter.cancelDiscovery);
    final uuid = javaUuid(service);
    final socket = guardJni(
      'Creating an RFCOMM socket',
      () => secure
          ? native.createRfcommSocketToServiceRecord(uuid)
          : native.createInsecureRfcommSocketToServiceRecord(uuid),
    );
    uuid.release();
    if (socket == null) {
      throw const ConnectionException('Android did not create the socket');
    }
    return AndroidSocketChannel.connect(socket, id);
  }
}
