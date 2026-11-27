import 'package:bt_kit/bt_kit.dart';

/// A precise sentence for a failed Bluetooth operation, with ATT codes, for
/// the GATT explorer. Other screens use `describeBluetoothError`.
String explainFailure(BluetoothException error) => switch (error) {
  GattException(:final error, :final nativeCode) => _gatt(error, nativeCode),
  OperationTimeoutException(:final timeout) =>
    'No answer within ${_duration(timeout)}',
  OperationCancelledException() => 'Cancelled',
  DisconnectedException(:final reason) =>
    reason == null
        ? 'Not connected to the device'
        : 'Disconnected: ${reason.cause.name}',
  AttributeInvalidatedException() =>
    'The device changed its services; discover them again',
  ConnectionException(:final nativeCode) =>
    nativeCode == null
        ? 'Could not connect'
        : 'Could not connect (status $nativeCode)',
  BluetoothUnavailableException(:final state) =>
    'Bluetooth is not available (${state.name})',
  BluetoothPermissionException() => 'The Bluetooth permission is missing',
  UnsupportedFeatureException(:final message) ||
  NativeOperationException(:final message) ||
  BondException(:final message) ||
  RangingException(:final message) ||
  ScanException(:final message) ||
  AdvertisingException(:final message) => message,
};

String _gatt(GattError error, int? nativeCode) => error == GattError.unknown
    ? 'GATT error ${nativeCode ?? 'unknown'}'
    : '${_sentence(error.name)} (ATT error ${_hex8(error.code)})';

/// `readNotPermitted` becomes `Read not permitted`.
String _sentence(String camelCase) {
  final words = camelCase
      .replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}')
      .trim();
  return words[0].toUpperCase() + words.substring(1);
}

String _hex8(int value) =>
    '0x${value.toRadixString(16).padLeft(2, '0').toUpperCase()}';

String _duration(Duration duration) => duration.inMilliseconds % 1000 == 0
    ? '${duration.inSeconds} s'
    : '${duration.inMilliseconds} ms';
