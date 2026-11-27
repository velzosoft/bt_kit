import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/classic/classic_bluetooth.dart'
    show createClassicBluetooth;
import 'package:bt_kit/src/native/android/bindings.dart' as android;
import 'package:bt_kit/src/platform/bond_backend.dart';
import 'package:bt_kit/src/platform/channel_backend.dart';
import 'package:bt_kit/src/platform/classic_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/capabilities.dart';
import '../fakes/channels.dart';
import '../fakes/test_host.dart';

final class FakeBond implements BondBackend {
  var state = BondState.none;
  final changes = StreamController<BondState>.broadcast(sync: true);

  /// Set to make pairing wait and cancelling fail, as on Android before
  /// API 37.
  Completer<void>? stuck;

  @override
  BondState get bondState => state;

  @override
  Stream<BondState> get bondStates => changes.stream;

  @override
  Future<void> createBond() async {
    changes.add(state = BondState.bonding);
    await stuck?.future;
    changes.add(state = BondState.bonded);
  }

  @override
  void cancelBond() {
    if (stuck != null) throw const NativeOperationException('not allowed');
  }

  @override
  Future<void> removeBond() async => changes.add(state = BondState.none);
}

final class FakeClassicDevice implements ClassicDeviceBackend {
  FakeClassicDevice(this.id, {this.name});

  @override
  final String id;

  @override
  final String? name;

  @override
  DeviceClass? get deviceClass => const DeviceClass(0x240404);

  @override
  android.BluetoothDevice get native => throw UnimplementedError();

  @override
  final FakeBond bond = FakeBond();

  final connects = <(BluetoothUuid, bool)>[];
  Completer<RfcommChannelBackend>? gate;

  @override
  Future<RfcommChannelBackend> connect(
    BluetoothUuid service, {
    required bool secure,
  }) {
    connects.add((service, secure));
    return gate?.future ??
        Future.value(FakeByteChannel<android.BluetoothSocket>(peerId: id));
  }
}

final class FakeRfcommServer implements RfcommServerBackend {
  final accepted = StreamController<RfcommChannelBackend>();
  var closed = false;

  @override
  android.BluetoothServerSocket get native => throw UnimplementedError();

  @override
  Stream<RfcommChannelBackend> get channels => accepted.stream;

  @override
  Future<void> close() async => closed = true;
}

final class FakeClassic implements ClassicBackend {
  final devices = <String, FakeClassicDevice>{};
  StreamController<ClassicHit>? inquiry;
  final servers = <(String, BluetoothUuid, bool, FakeRfcommServer)>[];

  @override
  Stream<ClassicHit> discover() {
    final controller = inquiry = StreamController<ClassicHit>();
    return controller.stream;
  }

  void found(FakeClassicDevice device, {int rssi = -50}) => inquiry!.add((
    device: device,
    name: device.name,
    rssi: rssi,
    deviceClass: device.deviceClass,
  ));

  @override
  Future<ClassicDeviceBackend?> device(String id) async => devices[id];

  @override
  Future<List<ClassicDeviceBackend>> bondedDevices() async => [
    for (final device in devices.values)
      if (device.bond.state == BondState.bonded) device,
  ];

  @override
  Future<RfcommServerBackend> listen(
    String name,
    BluetoothUuid service, {
    required bool secure,
  }) async {
    final server = FakeRfcommServer();
    servers.add((name, service, secure, server));
    return server;
  }
}

void main() {
  late FakeClassic backend;
  late TestHost host;
  late ClassicBluetooth classic;
  final printer = FakeClassicDevice('00:11:22:33:44:55', name: 'Printer');

  setUp(() {
    backend = FakeClassic()..devices[printer.id] = printer;
    host = TestHost();
    classic = createClassicBluetooth(backend, host);
  });

  test('discovery reports devices and ends with the inquiry', () async {
    final found = <DiscoveredDevice>[];
    final done = Completer<void>();
    classic.discover().listen(found.add, onDone: done.complete);
    await pumpEventQueue();
    expect(classic.isDiscovering, isTrue);

    backend.found(printer);
    await backend.inquiry!.close();
    await done.future;

    expect(found.single.device.id, printer.id);
    expect(found.single.name, 'Printer');
    expect(found.single.rssi, -50);
    expect(found.single.deviceClass?.major, MajorDeviceClass.audioVideo);
    expect(classic.isDiscovering, isFalse);
  });

  test('one discovery runs at a time', () async {
    final first = classic.discover().listen((_) {});
    await pumpEventQueue();

    await expectLater(classic.discover(), emitsError(isA<ScanException>()));

    await first.cancel();
    final second = classic.discover().listen((_) {});
    await pumpEventQueue();
    expect(classic.isDiscovering, isTrue);
    await second.cancel();
  });

  test('discovery needs the scan permission', () async {
    host.denied.add(BluetoothPermission.scan);

    await expectLater(
      classic.discover(),
      emitsError(isA<BluetoothPermissionException>()),
    );
    expect(classic.isDiscovering, isFalse);
  });

  test('a device is one object for as long as it is used', () async {
    final found = <DiscoveredDevice>[];
    classic.discover().listen(found.add);
    await pumpEventQueue();
    backend.found(printer);
    await pumpEventQueue();

    expect(await classic.device(printer.id), same(found.single.device));
  });

  test('connect opens an RFCOMM channel to the service', () async {
    final device = (await classic.device(printer.id))!;

    final channel = await device.connect(BluetoothUuid.serialPort);
    await channel.write([1, 2, 3]);

    expect(channel.service, BluetoothUuid.serialPort);
    expect(channel.peerId, printer.id);
    expect(printer.connects.single, (BluetoothUuid.serialPort, true));
  });

  test('a connect that times out closes the late channel', () async {
    final device = (await classic.device(printer.id))!;
    final gate = printer.gate = Completer();

    await expectLater(
      device.connect(
        BluetoothUuid.serialPort,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<OperationTimeoutException>()),
    );
    final late = FakeByteChannel<android.BluetoothSocket>();
    gate.complete(late);
    await pumpEventQueue();

    expect(late.isClosed, isTrue);
  });

  test('listen publishes a service and accepts channels', () async {
    final server = await classic.listen(
      service: BluetoothUuid.serialPort,
      name: 'Chat',
      secure: false,
    );
    final channels = <RfcommChannel>[];
    server.channels.listen(channels.add);

    final (name, service, secure, fake) = backend.servers.single;
    fake.accepted.add(FakeByteChannel<android.BluetoothSocket>());
    await pumpEventQueue();
    await server.close();

    expect((name, service, secure), ('Chat', BluetoothUuid.serialPort, false));
    expect(channels.single.service, BluetoothUuid.serialPort);
    expect(fake.closed, isTrue);
  });

  test('Classic devices bond like peripherals', () async {
    final device = (await classic.device(printer.id))!;

    await device.createBond();

    expect(device.bondState, BondState.bonded);
    expect((await classic.bondedDevices()).single, same(device));
  });

  test('a cancel the platform refuses does not hide the timeout', () async {
    final device = (await classic.device(printer.id))!;
    printer.bond.state = BondState.none;
    final stuck = printer.bond.stuck = Completer();

    await expectLater(
      device.createBond(timeout: const Duration(milliseconds: 10)),
      throwsA(isA<OperationTimeoutException>()),
    );
    stuck.complete();
    printer.bond.stuck = null;
  });

  test('iOS has no Bluetooth Classic API', () async {
    host.capabilities = capabilities(classic: false);

    expect(
      () => classic.device(printer.id),
      throwsA(isA<UnsupportedFeatureException>()),
    );
    await expectLater(
      classic.discover(),
      emitsError(isA<UnsupportedFeatureException>()),
    );
  });
}
