import 'package:bt_kit/bt_kit.dart';

/// A calm sentence for the user about [error].
String describeBluetoothError(BluetoothException error) => switch (error) {
  BluetoothUnavailableException(:final state) => switch (state) {
    AdapterState.poweredOff ||
    AdapterState.turningOff => 'Bluetooth is off. Turn it on and try again.',
    AdapterState.unauthorized =>
      'This app may not use Bluetooth. Allow it in the system settings.',
    AdapterState.unsupported => 'This phone has no Bluetooth Low Energy.',
    _ => 'Bluetooth is not ready yet. Try again in a moment.',
  },
  BluetoothPermissionException() =>
    'Bluetooth permission is off. Allow it in the system settings.',
  UnsupportedFeatureException(:final message) => _sentence(message),
  AdvertisingException(:final message) =>
    'Could not start advertising. ${_sentence(message)}',
  ScanException() => 'The scan stopped. Try again.',
  ConnectionException() => 'Could not connect. Move closer and try again.',
  BondException() => 'Pairing did not finish. Try again and confirm the code.',
  RangingException(:final message) => _sentence(message),
  DisconnectedException() =>
    'The connection dropped. Move closer and try again.',
  AttributeInvalidatedException() =>
    'The other device changed what it offers. Refresh and try again.',
  OperationTimeoutException() =>
    'The other device did not answer in time. Move closer and try again.',
  GattException(:final error) =>
    'The other device refused the request (${error.name}).',
  OperationCancelledException() => 'Cancelled.',
  NativeOperationException(:final message) => _sentence(message),
};

/// Whether [statuses] are all granted. Otherwise, why not.
String? describeMissingPermissions(
  Map<BluetoothPermission, PermissionStatus> statuses,
) {
  final missing = statuses.values.where((status) => !status.isGranted);
  if (missing.isEmpty) return null;
  if (missing.contains(PermissionStatus.notDeclared)) {
    return 'This build does not declare the Bluetooth permissions it needs. '
        'See the bt_kit README.';
  }
  return 'Bluetooth permission is off. Allow it in the system settings.';
}

String _sentence(String message) {
  final trimmed = message.trim();
  return trimmed.endsWith('.') ? trimmed : '$trimmed.';
}
