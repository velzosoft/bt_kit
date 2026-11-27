import 'dart:typed_data';

/// How the two phones connect: the receiver serves its L2CAP PSM in a GATT
/// characteristic as a little-endian uint16, and the sender streams the
/// file over that channel.
abstract final class BeamLink {
  /// An encrypted channel makes the phones pair first, which leaves a bond
  /// in the system settings after the app closes. File beam sends only the
  /// app's own pictures and test bytes, so it skips encryption.
  static const secure = false;

  static const chunkSize = 8 * 1024;

  /// How long the sender waits for the receiver's answer.
  static const answerTimeout = Duration(seconds: 15);

  static Uint8List encodePsm(int psm) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, psm, Endian.little);

  /// The PSM in a characteristic value, or null if the value is malformed.
  static int? decodePsm(List<int> value) {
    if (value.length != 2) return null;
    final psm = value[0] | value[1] << 8;
    return psm == 0 ? null : psm;
  }
}
