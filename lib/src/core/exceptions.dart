import '../models/adapter_state.dart';
import '../models/disconnect_reason.dart';
import '../models/permission.dart';

/// Every failure reported by the unified API.
///
/// [nativeCode] and [nativeError] carry the platform's own status code or
/// error object when there is one.
sealed class BluetoothException implements Exception {
  const BluetoothException(this.message, {this.nativeCode, this.nativeError});

  final String message;
  final int? nativeCode;
  final Object? nativeError;

  @override
  String toString() {
    final code = nativeCode == null ? '' : ' (native code $nativeCode)';
    return '$runtimeType: $message$code';
  }
}

/// The adapter is off, resetting, unsupported or unauthorized.
final class BluetoothUnavailableException extends BluetoothException {
  BluetoothUnavailableException(this.state)
    : super('Bluetooth is not available: ${state.name}');

  final AdapterState state;
}

/// A required permission is not granted or not declared by the app.
final class BluetoothPermissionException extends BluetoothException {
  const BluetoothPermissionException(this.statuses, String message)
    : super(message);

  final Map<BluetoothPermission, PermissionStatus> statuses;
}

/// The platform or device does not offer the requested feature. Check
/// `BtKit.capabilities` first to avoid it.
final class UnsupportedFeatureException extends BluetoothException {
  const UnsupportedFeatureException(this.feature, String message)
    : super(message);

  final String feature;
}

/// A scan could not start or stopped with an error.
final class ScanException extends BluetoothException {
  const ScanException(super.message, {super.nativeCode, super.nativeError});
}

/// Advertising could not start.
final class AdvertisingException extends BluetoothException {
  const AdvertisingException(
    super.message, {
    super.nativeCode,
    super.nativeError,
  });
}

/// A connection attempt failed.
final class ConnectionException extends BluetoothException {
  const ConnectionException(
    super.message, {
    super.nativeCode,
    super.nativeError,
  });
}

/// Pairing failed, was rejected, or a bond could not be removed.
final class BondException extends BluetoothException {
  const BondException(super.message, {super.nativeCode, super.nativeError});
}

/// A distance measurement could not start or stopped with an error.
final class RangingException extends BluetoothException {
  const RangingException(super.message, {super.nativeCode, super.nativeError});
}

/// The peripheral is not connected, or the link dropped while an operation
/// was pending.
final class DisconnectedException extends BluetoothException {
  const DisconnectedException([
    super.message = 'The peripheral is not connected',
    this.reason,
  ]);

  /// Why the link dropped, when it dropped during the operation.
  final DisconnectReason? reason;

  @override
  String toString() =>
      reason == null ? super.toString() : '${super.toString()}: $reason';
}

/// The peripheral changed its GATT database and the attribute is no longer
/// valid. Call `Peripheral.discoverServices` again.
final class AttributeInvalidatedException extends BluetoothException {
  const AttributeInvalidatedException(super.message);
}

/// The remote device answered a GATT request with an error.
final class GattException extends BluetoothException {
  GattException(
    this.error,
    String operation, {
    super.nativeCode,
    super.nativeError,
  }) : super('$operation failed: ${error.name}');

  final GattError error;
}

/// The platform refused to start an operation.
final class NativeOperationException extends BluetoothException {
  const NativeOperationException(
    super.message, {
    super.nativeCode,
    super.nativeError,
  });
}

/// An operation did not complete within its timeout.
final class OperationTimeoutException extends BluetoothException {
  OperationTimeoutException(String operation, this.timeout)
    : super('$operation timed out after $timeout');

  final Duration timeout;
}

/// An operation was cancelled through its `CancelToken`.
final class OperationCancelledException extends BluetoothException {
  const OperationCancelledException([this.reason])
    : super('The operation was cancelled');

  final Object? reason;
}

/// ATT error codes from the Bluetooth Core Specification, Vol 3, Part F.
enum GattError {
  invalidHandle(0x01),
  readNotPermitted(0x02),
  writeNotPermitted(0x03),
  invalidPdu(0x04),
  insufficientAuthentication(0x05),
  requestNotSupported(0x06),
  invalidOffset(0x07),
  insufficientAuthorization(0x08),
  prepareQueueFull(0x09),
  attributeNotFound(0x0a),
  attributeNotLong(0x0b),
  insufficientEncryptionKeySize(0x0c),
  invalidAttributeValueLength(0x0d),
  unlikelyError(0x0e),
  insufficientEncryption(0x0f),
  unsupportedGroupType(0x10),
  insufficientResources(0x11),
  databaseOutOfSync(0x12),
  valueNotAllowed(0x13),
  unknown(-1);

  const GattError(this.code);

  final int code;

  static GattError fromCode(int code) =>
      values.firstWhere((e) => e.code == code, orElse: () => unknown);
}
