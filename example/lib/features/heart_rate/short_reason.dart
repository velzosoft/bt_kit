import 'package:bt_kit/bt_kit.dart';

/// A short, calm reason for a player's tile.
String shortReason(BluetoothException error) => switch (error) {
  BluetoothUnavailableException(state: AdapterState.unauthorized) ||
  BluetoothPermissionException() => 'Bluetooth permission is off',
  BluetoothUnavailableException() => 'Bluetooth is off',
  DisconnectedException() => 'Signal lost',
  AttributeInvalidatedException() => 'The sensor changed',
  ConnectionException() => 'Could not connect',
  BondException() => 'Pairing failed',
  RangingException() => 'Distance unavailable',
  OperationTimeoutException() => 'No answer',
  GattException(:final error) => 'The sensor refused (${error.name})',
  NativeOperationException() => 'The phone refused the request',
  UnsupportedFeatureException(:final message) => message,
  OperationCancelledException() => 'Cancelled',
  ScanException() || AdvertisingException() => error.message,
};
