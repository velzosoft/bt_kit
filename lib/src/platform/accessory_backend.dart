import '../native/ios/bindings.dart' as ios;
import 'channel_backend.dart';

/// MFi accessories through ExternalAccessory (iOS).
abstract interface class AccessoryBackend {
  List<AccessoryBackendItem> get connected;

  /// Connections and disconnections; reported while listened.
  Stream<({AccessoryBackendItem accessory, bool connected})> get changes;

  /// Shows the system picker for Bluetooth accessories; completes when it
  /// is dismissed. A chosen accessory connects through [changes].
  Future<void> showBluetoothPicker();
}

abstract interface class AccessoryBackendItem {
  int get connectionId;
  String get name;
  String get manufacturer;
  String get modelNumber;
  String get serialNumber;
  String get firmwareRevision;
  String get hardwareRevision;
  List<String> get protocols;
  bool get isConnected;
  ios.EAAccessory get native;

  Future<ByteChannelBackend<ios.EASession>> openSession(String protocol);
}
