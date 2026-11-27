import 'package:meta/meta.dart';

enum DisconnectCause {
  /// This app disconnected.
  requested,

  /// The peripheral ended the connection.
  remote,

  /// The link timed out, usually because the peripheral went out of range.
  linkLoss,

  /// The connection attempt failed.
  failedToConnect,

  /// Bluetooth turned off.
  adapterOff,

  unknown,
}

/// Why a peripheral's connection ended.
@immutable
final class DisconnectReason {
  const DisconnectReason(this.cause, {this.nativeCode, required this.at});

  final DisconnectCause cause;

  /// Android: the `onConnectionStateChange` status. iOS: the `CBError` code.
  final int? nativeCode;
  final DateTime at;

  @override
  String toString() {
    final code = nativeCode == null ? '' : ' (native code $nativeCode)';
    return '${cause.name}$code';
  }
}
