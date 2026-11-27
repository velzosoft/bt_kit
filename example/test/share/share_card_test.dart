import 'dart:typed_data';

import 'package:bt_radar/bluetooth/device_kind.dart';
import 'package:bt_radar/features/share/share_card.dart';
import 'package:bt_radar/widgets/radar_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const card = ShareCardData(
    count: 143,
    breakdown: [MapEntry(DeviceKind.phone, 61), MapEntry(DeviceKind.audio, 32)],
    blips: [
      Blip(id: '0', kind: DeviceKind.phone, radius: 0.4, angle: 1),
      Blip(id: '1', kind: DeviceKind.audio, radius: 0.8, angle: 4),
    ],
  );

  test('the headline uses the count', () {
    expect(card.headline, '143 Bluetooth devices around me');
    expect(
      const ShareCardData(count: 1, breakdown: [], blips: []).headline,
      '1 Bluetooth device around me',
    );
  });

  test('captions are trimmed', () {
    expect(card.withCaption('  Heathrow T5 ').caption, 'Heathrow T5');
  });

  testWidgets('renders a 1080 × 1350 PNG', (tester) async {
    final png = (await tester.runAsync(
      () => renderShareCard(card.withCaption('Heathrow T5')),
    ))!;
    final header = ByteData.sublistView(png);
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    expect(header.getUint32(16), 1080);
    expect(header.getUint32(20), 1350);
  });
}
