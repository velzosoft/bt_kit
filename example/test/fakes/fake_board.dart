import 'dart:convert';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/testing.dart';
import 'package:bt_radar/bluetooth/app_uuids.dart';

/// A Hello board served from the same `LocalService` models a phone would
/// use, with the firmware's command validation.
final class FakeBoard {
  FakeBoard({
    this.id = 'E4:0A:C4:07:29:6A',
    this._rssi = -50,
    Duration? heldFor,
  }) : _initialButton = heldFor == null
           ? _button(pressed: false, presses: 0, held: Duration.zero)
           : _button(pressed: true, presses: 1, held: heldFor),
       presses = heldFor == null ? 0 : 1;

  final String id;
  final List<int> _initialButton;
  final int _rssi;

  /// Every LED command the board accepted.
  final commands = <Uint8List>[];

  int presses;

  String get name =>
      'bt_kit Board ${id.replaceAll(':', '').substring(8).toUpperCase()}';

  late final button = LocalCharacteristic(
    AppUuids.boardButton,
    properties: const CharacteristicProperties.of(read: true, notify: true),
    value: _initialButton,
  );

  late final ledCommand = LocalCharacteristic(
    AppUuids.boardLedCommand,
    properties: const CharacteristicProperties.of(
      write: true,
      writeWithoutResponse: true,
    ),
    onWrite: _onCommand,
  );

  late final led = LocalCharacteristic(
    AppUuids.boardLed,
    properties: const CharacteristicProperties.of(read: true, notify: true),
    value: const [0x02, 0x03, 0xff, 0x90, 0x00, 0x00],
  );

  late final info = LocalCharacteristic(
    AppUuids.boardInfo,
    properties: const CharacteristicProperties.of(read: true),
    value: [0x00, ...utf8.encode('esp32 rev0.0 esp-idf v6.1.1 fw 1.0.0')],
  );

  late final peripheral = FakePeripheral(
    id: id,
    advertisement: AdvertisementData(
      localName: name,
      serviceUuids: [AppUuids.board],
    ),
    rssi: _rssi,
    services: [
      LocalService(AppUuids.board, [button, ledCommand, led, info]),
    ],
  );

  bool get isSubscribedToButton => peripheral.subscription(button) != null;

  bool get isSubscribedToLed => peripheral.subscription(led) != null;

  Future<void> press() => peripheral.notify(
    button,
    _button(pressed: true, presses: ++presses, held: Duration.zero),
  );

  Future<void> release(Duration held) => peripheral.notify(
    button,
    _button(pressed: false, presses: presses, held: held),
  );

  /// Reports the LED: state, pattern, color and flash count.
  Future<void> showLed(List<int> value) => peripheral.notify(led, value);

  void _onCommand(WriteRequest request) {
    final error = switch (request.value) {
      [] => GattError.invalidAttributeValueLength,
      [0x00] => null,
      [0x00, ...] => GattError.invalidAttributeValueLength,
      [0x01, _, _, _, final count] =>
        count == 0 || count > 10 ? GattError.valueNotAllowed : null,
      [0x01, ...] => GattError.invalidAttributeValueLength,
      _ => GattError.valueNotAllowed,
    };
    if (error != null) throw GattException(error, 'LED command');
    commands.add(request.value);
  }

  static List<int> _button({
    required bool pressed,
    required int presses,
    required Duration held,
  }) {
    final ms = held.inMilliseconds;
    return [
      if (pressed) 0x01 else 0x00,
      presses & 0xff,
      presses >> 8 & 0xff,
      for (var i = 0; i < 4; i++) ms >> (8 * i) & 0xff,
    ];
  }
}
