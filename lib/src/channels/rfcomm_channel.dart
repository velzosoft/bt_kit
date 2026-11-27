part of 'byte_channel.dart';

/// An RFCOMM socket to a Bluetooth Classic device, such as a Serial Port
/// Profile (SPP) device (Android).
///
/// Connect with `ClassicDevice.connect`, or accept them from an
/// [RfcommServer].
final class RfcommChannel extends ByteChannel {
  RfcommChannel._(RfcommChannelBackend backend, this.service)
    : super._(backend, BtLog.classic, '${backend.peerId} RFCOMM $service');

  /// The service record the channel was opened for.
  final BluetoothUuid service;

  android.BluetoothSocket get native =>
      (_backend as RfcommChannelBackend).native;
}

/// An RFCOMM service that accepts incoming [RfcommChannel]s, created with
/// `ClassicBluetooth.listen`.
final class RfcommServer {
  RfcommServer._(this._backend, this.service);

  final RfcommServerBackend _backend;

  /// The service UUID remote devices connect to, published in the SDP
  /// record.
  final BluetoothUuid service;

  android.BluetoothServerSocket get native => _backend.native;

  /// Channels opened by remote devices. Listen once.
  late final Stream<RfcommChannel> channels = _backend.channels.map(
    (channel) => RfcommChannel._(channel, service),
  );

  /// Stops accepting channels and removes the service record. Open channels
  /// stay open.
  Future<void> close() => _backend.close();
}

RfcommChannel createRfcommChannel(
  RfcommChannelBackend backend,
  BluetoothUuid service,
) => RfcommChannel._(backend, service);

RfcommServer createRfcommServer(
  RfcommServerBackend backend,
  BluetoothUuid service,
) => RfcommServer._(backend, service);
