part of 'byte_channel.dart';

/// An L2CAP connection-oriented channel, with much higher throughput than
/// GATT.
///
/// Open one with `Peripheral.openL2capChannel`, or accept them from an
/// [L2capServer].
final class L2capChannel extends ByteChannel {
  L2capChannel._(L2capChannelBackend backend)
    : _l2cap = backend,
      super._(backend, BtLog.l2cap, '${backend.peerId} PSM ${backend.psm}');

  final L2capChannelBackend _l2cap;

  int get psm => _l2cap.psm;

  /// `BluetoothSocket` on Android, `CBL2CAPChannel` on iOS.
  L2capChannelHandle get native => _l2cap.native;
}

/// A published PSM that accepts incoming [L2capChannel]s, created with
/// `BtKit.publishL2capChannel`.
final class L2capServer {
  L2capServer._(this._backend);

  final L2capServerBackend _backend;

  /// The PSM centrals connect to. Share it with them, for example in a GATT
  /// characteristic.
  int get psm => _backend.psm;

  /// `BluetoothServerSocket` on Android, `CBPeripheralManager` on iOS.
  L2capServerHandle get native => _backend.native;

  /// Channels opened by remote centrals. Listen once.
  late final Stream<L2capChannel> channels = _backend.channels.map(
    L2capChannel._,
  );

  /// Stops accepting channels. Open channels stay open.
  Future<void> close() => _backend.close();
}

L2capChannel createL2capChannel(L2capChannelBackend backend) =>
    L2capChannel._(backend);

L2capServer createL2capServer(L2capServerBackend backend) =>
    L2capServer._(backend);
