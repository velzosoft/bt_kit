import 'dart:typed_data';

import '../central/native_types.dart';
import '../native/android/bindings.dart' as android;

/// An open byte stream: an L2CAP channel, an RFCOMM socket or an accessory
/// session. [N] is the Layer 1 object behind it.
abstract interface class ByteChannelBackend<N extends Object> {
  /// The remote device: a peripheral, central, Classic device or accessory.
  String get peerId;

  N get native;

  /// Received data. Ends when either side closes the channel.
  Stream<Uint8List> get input;

  /// Completes once the platform accepted every byte.
  Future<void> write(Uint8List data);

  Future<void> close();

  /// Completes when the channel is closed, by either side.
  Future<void> get done;
}

/// An open L2CAP connection-oriented channel.
abstract interface class L2capChannelBackend
    implements ByteChannelBackend<L2capChannelHandle> {
  int get psm;
}

/// A published PSM that accepts incoming channels.
abstract interface class L2capServerBackend {
  int get psm;
  L2capServerHandle get native;
  Stream<L2capChannelBackend> get channels;
  Future<void> close();
}

/// An RFCOMM socket (Android).
typedef RfcommChannelBackend = ByteChannelBackend<android.BluetoothSocket>;

/// A listening RFCOMM service that accepts incoming sockets (Android).
abstract interface class RfcommServerBackend {
  android.BluetoothServerSocket get native;
  Stream<RfcommChannelBackend> get channels;
  Future<void> close();
}
