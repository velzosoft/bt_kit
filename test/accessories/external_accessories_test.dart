import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/accessories/external_accessories.dart'
    show createExternalAccessories;
import 'package:bt_kit/src/native/ios/bindings.dart' as ios;
import 'package:bt_kit/src/platform/accessory_backend.dart';
import 'package:bt_kit/src/platform/channel_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/capabilities.dart';
import '../fakes/channels.dart';

final class FakeAccessory implements AccessoryBackendItem {
  FakeAccessory(this.connectionId, {this.isConnected = true});

  @override
  final int connectionId;

  @override
  bool isConnected;

  final sessions = <String>[];

  @override
  String get name => 'Sensor';

  @override
  String get manufacturer => 'Example';

  @override
  String get modelNumber => 'S1';

  @override
  String get serialNumber => '0001';

  @override
  String get firmwareRevision => '1.0';

  @override
  String get hardwareRevision => 'A';

  @override
  List<String> get protocols => const ['com.example.sensor'];

  @override
  ios.EAAccessory get native => throw UnimplementedError();

  @override
  Future<ByteChannelBackend<ios.EASession>> openSession(String protocol) async {
    sessions.add(protocol);
    return FakeByteChannel<ios.EASession>(peerId: '$connectionId');
  }
}

final class FakeAccessories implements AccessoryBackend {
  final items = <FakeAccessory>[];
  final events =
      StreamController<
        ({AccessoryBackendItem accessory, bool connected})
      >.broadcast();
  var pickerShown = 0;

  @override
  List<AccessoryBackendItem> get connected => items;

  @override
  Stream<({AccessoryBackendItem accessory, bool connected})> get changes =>
      events.stream;

  @override
  Future<void> showBluetoothPicker() async => pickerShown++;
}

void main() {
  late FakeAccessories backend;
  late BluetoothCapabilities current;
  late ExternalAccessories accessories;
  final sensor = FakeAccessory(7);

  setUp(() {
    backend = FakeAccessories()..items.add(sensor);
    current = capabilities();
    accessories = createExternalAccessories(backend, () => current);
  });

  test('lists connected accessories as stable objects', () {
    final first = accessories.connected.single;

    expect(first.name, 'Sensor');
    expect(first.protocols, ['com.example.sensor']);
    expect(accessories.connected.single, same(first));
  });

  test('reports connections and disconnections', () async {
    final events = <AccessoryEvent>[];
    accessories.changes.listen(events.add);
    final other = FakeAccessory(8);

    backend.events
      ..add((accessory: other, connected: true))
      ..add((accessory: other, connected: false));
    await pumpEventQueue();

    expect(events.map((e) => (e.accessory.connectionId, e.connected)), [
      (8, true),
      (8, false),
    ]);
  });

  test('a session is a byte channel for one protocol', () async {
    final session = await accessories.connected.single.openSession(
      'com.example.sensor',
    );

    await session.write([0x01]);

    expect(session.protocol, 'com.example.sensor');
    expect(session.accessory.connectionId, 7);
    expect(sensor.sessions, ['com.example.sensor']);
  });

  test('a session needs a protocol the accessory speaks', () {
    expect(
      () => accessories.connected.single.openSession('com.example.other'),
      throwsArgumentError,
    );
  });

  test('a disconnected accessory opens no session', () async {
    final accessory = accessories.connected.single;
    sensor.isConnected = false;

    await expectLater(
      accessory.openSession('com.example.sensor'),
      throwsA(isA<DisconnectedException>()),
    );
    sensor.isConnected = true;
  });

  test('shows the Bluetooth accessory picker', () async {
    await accessories.showBluetoothPicker();

    expect(backend.pickerShown, 1);
  });

  test('Android has no ExternalAccessory', () async {
    current = capabilities(externalAccessory: false);

    expect(accessories.connected, isEmpty);
    await expectLater(
      accessories.showBluetoothPicker(),
      throwsA(isA<UnsupportedFeatureException>()),
    );
  });
}
