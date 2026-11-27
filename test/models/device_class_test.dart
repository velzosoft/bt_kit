import 'package:bt_kit/bt_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the major class, device bits and services', () {
    const headphones = DeviceClass(0x240418);

    expect(headphones.major, MajorDeviceClass.audioVideo);
    expect(headphones.device, 0x0418);
    expect(headphones.services, {DeviceService.audio, DeviceService.rendering});
  });

  test('an unknown major class is uncategorized', () {
    expect(const DeviceClass(0x001e00).major, MajorDeviceClass.uncategorized);
    expect(const DeviceClass(0).services, isEmpty);
  });

  test('compares by value', () {
    expect(const DeviceClass(0x5a020c), const DeviceClass(0x5a020c));
    expect(const DeviceClass(0x5a020c).major, MajorDeviceClass.phone);
  });
}
