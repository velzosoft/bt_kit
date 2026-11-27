part of 'byte_channel.dart';

/// A session with an MFi accessory over one of its protocols (iOS).
///
/// Open one with [ExternalAccessory.openSession].
final class AccessorySession extends ByteChannel {
  AccessorySession._(
    ByteChannelBackend<ios.EASession> backend,
    this.accessory,
    this.protocol,
  ) : super._(backend, BtLog.accessory, '${accessory.name} $protocol');

  final ExternalAccessory accessory;

  /// The protocol string, such as `com.example.sensor`. The app lists it
  /// under `UISupportedExternalAccessoryProtocols` in its `Info.plist`.
  final String protocol;

  ios.EASession get native =>
      (_backend as ByteChannelBackend<ios.EASession>).native;
}

AccessorySession createAccessorySession(
  ByteChannelBackend<ios.EASession> backend,
  ExternalAccessory accessory,
  String protocol,
) => AccessorySession._(backend, accessory, protocol);
