import 'package:objective_c/objective_c.dart' as objc;

import '../core/native_handle.dart';
import '../native/android/bindings.dart' as android;
import '../native/ios/bindings.dart' as ios;

/// The Android objects behind a `Peripheral`.
final class AndroidPeripheral {
  AndroidPeripheral(this.device, this._gatt);

  final android.BluetoothDevice device;
  final android.BluetoothGatt? Function() _gatt;

  /// The open GATT client, while one exists.
  android.BluetoothGatt? get gatt => _gatt();
}

/// The iOS objects behind an `Advertisement`, as CoreBluetooth delivered
/// them to `centralManager:didDiscoverPeripheral:advertisementData:RSSI:`.
typedef IosAdvertisement = ({
  ios.CBPeripheral peripheral,
  objc.NSDictionary advertisementData,
  objc.NSNumber rssi,
});

typedef AdapterHandle =
    NativeHandle<android.BluetoothAdapter, ios.CBCentralManager>;
typedef AdvertisementHandle =
    NativeHandle<android.ScanResult, IosAdvertisement>;
typedef PeripheralHandle = NativeHandle<AndroidPeripheral, ios.CBPeripheral>;
typedef ServiceHandle =
    NativeHandle<android.BluetoothGattService, ios.CBService>;
typedef CharacteristicHandle =
    NativeHandle<android.BluetoothGattCharacteristic, ios.CBCharacteristic>;
typedef DescriptorHandle =
    NativeHandle<android.BluetoothGattDescriptor, ios.CBDescriptor>;
typedef CentralHandle = NativeHandle<android.BluetoothDevice, ios.CBCentral>;
typedef ServerHandle =
    NativeHandle<android.BluetoothGattServer, ios.CBPeripheralManager>;
typedef LocalServiceHandle =
    NativeHandle<android.BluetoothGattService, ios.CBMutableService>;
typedef LocalCharacteristicHandle =
    NativeHandle<
      android.BluetoothGattCharacteristic,
      ios.CBMutableCharacteristic
    >;
typedef AdvertisingHandle =
    NativeHandle<android.AdvertisingSet, ios.CBPeripheralManager>;
typedef L2capChannelHandle =
    NativeHandle<android.BluetoothSocket, ios.CBL2CAPChannel>;
typedef L2capServerHandle =
    NativeHandle<android.BluetoothServerSocket, ios.CBPeripheralManager>;
typedef CompanionHandle =
    NativeHandle<android.AssociationInfo, ios.ASAccessory>;
