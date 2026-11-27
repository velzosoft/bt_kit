import '../../core/exceptions.dart';
import '../../models/adapter_state.dart';
import '../../models/advertise_options.dart';
import '../../native/android/bindings.dart';
import '../channel_backend.dart';
import '../peripheral_role_backend.dart';
import 'android_advertising.dart';
import 'android_central.dart';
import 'android_gatt_server.dart';
import 'android_sockets.dart';
import 'jni_conversions.dart';

/// The peripheral role on Android: `BluetoothGattServer`,
/// `BluetoothLeAdvertiser` and L2CAP server sockets.
final class AndroidPeripheralRole implements PeripheralRoleBackend {
  AndroidPeripheralRole(this._central);

  final AndroidCentral _central;

  @override
  Future<AdapterState> settledState() => _central.settledAdapterState();

  @override
  Future<ServerBackend> openServer() =>
      AndroidGattServer.open(_central.context, _central.manager);

  @override
  Future<AdvertisingBackend> startAdvertising(AdvertiseOptions options) {
    final advertiser = _central.adapter.bluetoothLeAdvertiser;
    if (advertiser == null) {
      throw BluetoothUnavailableException(_central.adapterState);
    }
    return AndroidAdvertising.start(advertiser, options);
  }

  @override
  Future<L2capServerBackend> publishL2cap({required bool secure}) async {
    final adapter = _central.adapter;
    return AndroidL2capServer(
      guardJni(
        'Publishing an L2CAP channel',
        () => secure
            ? adapter.listenUsingL2capChannel()
            : adapter.listenUsingInsecureL2capChannel(),
      ),
    );
  }

  /// Android keeps no peripheral-role state across process restarts.
  @override
  Stream<PeripheralRoleRestoration> get restorations => const Stream.empty();
}
