import 'package:bt_radar/bluetooth/rssi_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts empty and takes the first reading as is', () {
    final filter = RssiFilter();
    expect(filter.value, isNull);
    expect(filter.add(-70), -70);
  });

  test('the median removes a single spike', () {
    final filter = RssiFilter(alpha: 1);
    for (final rssi in [-70, -70, -70, -70]) {
      filter.add(rssi);
    }
    expect(filter.add(-30), -70);
  });

  test('the moving average approaches a new level gradually', () {
    final filter = RssiFilter(window: 1, alpha: 0.3);
    filter.add(-80);
    expect(filter.add(-60), closeTo(-74, 1e-9));
    expect(filter.add(-60), closeTo(-69.8, 1e-9));
  });

  test('uses the mean of the middle pair for an even window', () {
    final filter = RssiFilter(window: 4, alpha: 1);
    filter
      ..add(-80)
      ..add(-70)
      ..add(-60);
    expect(filter.add(-50), -65);
  });

  test('ignores the iOS "unavailable" value 127', () {
    final filter = RssiFilter();
    filter.add(-65);
    expect(filter.add(RssiFilter.unavailable), -65);
  });

  test('reset forgets everything', () {
    final filter = RssiFilter()..add(-65);
    filter.reset();
    expect(filter.value, isNull);
    expect(filter.add(-90), -90);
  });
}
