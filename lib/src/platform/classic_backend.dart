import '../core/bluetooth_uuid.dart';
import '../models/device_class.dart';
import '../native/android/bindings.dart' as android;
import 'bond_backend.dart';
import 'channel_backend.dart';

/// Bluetooth Classic (BR/EDR): discovery and RFCOMM.
abstract interface class ClassicBackend {
  /// Runs one inquiry: starts on listen, stops on cancel, and ends when the
  /// platform finishes it. Only one runs at a time.
  Stream<ClassicHit> discover();

  Future<ClassicDeviceBackend?> device(String id);

  Future<List<ClassicDeviceBackend>> bondedDevices();

  /// Publishes an SDP record for [service] and accepts RFCOMM sockets.
  Future<RfcommServerBackend> listen(
    String name,
    BluetoothUuid service, {
    required bool secure,
  });
}

typedef ClassicHit = ({
  ClassicDeviceBackend device,
  String? name,
  int? rssi,
  DeviceClass? deviceClass,
});

abstract interface class ClassicDeviceBackend {
  String get id;
  String? get name;
  DeviceClass? get deviceClass;
  android.BluetoothDevice get native;
  BondBackend get bond;

  /// Connects an RFCOMM socket to [service], found through SDP.
  Future<RfcommChannelBackend> connect(
    BluetoothUuid service, {
    required bool secure,
  });
}
