import 'dart:math';
import 'dart:typed_data';

import '../../../bluetooth/scanner.dart';
import '../../share/share_card.dart';
import 'transfer_units.dart';

/// What File beam can send. With no photo picker, it beams pictures the app
/// makes itself, or test bytes.
enum BeamPayloadKind {
  snapshot('Radar snapshot'),
  test('1 MB test');

  const BeamPayloadKind(this.label);

  final String label;
}

final class BeamPayload {
  const BeamPayload(this.name, this.bytes);

  static const testLength = TransferUnits.megabyte;

  /// The radar share card, as a PNG.
  static Future<BeamPayload> snapshot(Scanner scanner) async => BeamPayload(
    'bluetooth-radar.png',
    await renderShareCard(ShareCardData.of(scanner)),
  );

  /// Random bytes for measuring throughput.
  factory BeamPayload.test({int length = testLength, Random? random}) {
    final source = random ?? Random();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = source.nextInt(256);
    }
    return BeamPayload('throughput-test.bin', bytes);
  }

  static Future<BeamPayload> of(BeamPayloadKind kind, Scanner scanner) =>
      switch (kind) {
        BeamPayloadKind.snapshot => snapshot(scanner),
        BeamPayloadKind.test => Future.value(BeamPayload.test()),
      };

  final String name;
  final Uint8List bytes;
}

const _pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

bool hasPngSignature(List<int> bytes) {
  if (bytes.length < _pngSignature.length) return false;
  for (var i = 0; i < _pngSignature.length; i++) {
    if (bytes[i] != _pngSignature[i]) return false;
  }
  return true;
}
