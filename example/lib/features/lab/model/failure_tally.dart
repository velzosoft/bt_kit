import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import 'lab_failure.dart';

/// Failures counted by exception type and by the phase they happened in,
/// with the first few messages kept as samples.
final class FailureTally {
  static const maxSamples = 20;

  final byType = <String, int>{};
  final byPhase = <String, int>{};
  final samples = <String>[];
  var count = 0;

  bool get isEmpty => count == 0;

  void add(String phase, Object error, {String? context}) {
    count++;
    byType.update(nameOf(error), (n) => n + 1, ifAbsent: () => 1);
    byPhase.update(phase, (n) => n + 1, ifAbsent: () => 1);
    if (samples.length < maxSamples) {
      samples.add(
        '${context == null ? '' : '$context '}$phase: ${describe(error)}',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'byType': byType,
    'byPhase': byPhase,
    'samples': samples,
  };

  /// A stable name for [error]'s type, such as
  /// `GattException(readNotPermitted)`.
  static String nameOf(Object error) => switch (error) {
    BluetoothException() => _bluetoothName(error),
    LabFailure(:final kind) => kind,
    TimeoutException() => 'TimeoutException',
    _ => error.runtimeType.toString(),
  };

  static String describe(Object error) => switch (error) {
    BluetoothException(:final message, :final nativeCode) =>
      '${nameOf(error)}: $message'
          '${nativeCode == null ? '' : ' (native code $nativeCode)'}',
    LabFailure(:final message) => '${nameOf(error)}: $message',
    _ => '$error',
  };

  static String _bluetoothName(BluetoothException error) => switch (error) {
    GattException(:final error) => 'GattException(${error.name})',
    BluetoothUnavailableException() => 'BluetoothUnavailableException',
    BluetoothPermissionException() => 'BluetoothPermissionException',
    UnsupportedFeatureException() => 'UnsupportedFeatureException',
    ScanException() => 'ScanException',
    AdvertisingException() => 'AdvertisingException',
    ConnectionException() => 'ConnectionException',
    BondException() => 'BondException',
    RangingException() => 'RangingException',
    DisconnectedException() => 'DisconnectedException',
    AttributeInvalidatedException() => 'AttributeInvalidatedException',
    NativeOperationException() => 'NativeOperationException',
    OperationTimeoutException() => 'OperationTimeoutException',
    OperationCancelledException() => 'OperationCancelledException',
  };
}
