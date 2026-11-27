import 'package:meta/meta.dart';

/// The radio a link uses.
enum LinkTransport { le, classic, unknown }

/// A device connected to or disconnected from this phone, by any app or
/// by the system.
@immutable
final class SystemConnectionEvent {
  const SystemConnectionEvent({
    required this.deviceId,
    required this.connected,
    required this.transport,
    required this.at,
  });

  /// Android: the MAC address. iOS: the peripheral's identifier.
  final String deviceId;
  final bool connected;

  /// iOS reports LE links only.
  final LinkTransport transport;
  final DateTime at;

  @override
  String toString() =>
      'SystemConnectionEvent($deviceId, '
      '${connected ? 'connected' : 'disconnected'}, ${transport.name})';
}
