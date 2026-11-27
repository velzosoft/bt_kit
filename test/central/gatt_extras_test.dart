import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final serviceUuid = BluetoothUuid.short(0x1810);
final sinkUuid = BluetoothUuid.short(0x2a35);
final batteryUuid = BluetoothUuid.short(0x180f);
final levelUuid = BluetoothUuid.short(0x2a19);

void main() {
  late FakeBluetooth bluetooth;
  late FakePeripheral sensor;
  late List<String> served;
  late Completer<void>? writeGate;
  late LocalService battery;
  late LocalService main;

  void install([
    BluetoothCapabilities capabilities = FakeBluetooth.androidCapabilities,
  ]) {
    bluetooth = FakeBluetooth.install(capabilities: capabilities);
    served = [];
    writeGate = null;
    final sink = LocalCharacteristic(
      sinkUuid,
      properties: const CharacteristicProperties.of(
        read: true,
        write: true,
        writeWithoutResponse: true,
      ),
      onRead: (_) {
        served.add('read');
        return [0x00];
      },
      onWrite: (request) async {
        served.add('write ${request.value.length}');
        await writeGate?.future;
      },
    );
    battery = LocalService(batteryUuid, [
      LocalCharacteristic(
        levelUuid,
        properties: const CharacteristicProperties.of(read: true),
        value: [0x64],
      ),
    ], isPrimary: false);
    main = LocalService(serviceUuid, [sink], includedServices: [battery]);
    sensor = FakePeripheral(id: 'C4:7C:8D:6A:12:34', services: [battery, main]);
    bluetooth.add(sensor);
  }

  tearDown(FakeBluetooth.uninstall);

  Future<Peripheral> connected({int? mtu}) async {
    final peripheral = (await BtKit.instance.peripheral(sensor.id))!;
    await peripheral.connect(mtu: mtu);
    await peripheral.discoverServices();
    return peripheral;
  }

  GattCharacteristic sinkOf(Peripheral peripheral) =>
      peripheral.characteristic(serviceUuid, sinkUuid)!;

  group('writeChunked', () {
    setUp(install);

    test('splits the value by the maximum write length', () async {
      final peripheral = await connected();
      final sink = sinkOf(peripheral);
      final progress = <(int, int)>[];

      await sink.writeChunked(
        List.generate(50, (i) => i),
        onProgress: (sent, total) => progress.add((sent, total)),
      );

      expect(served, ['write 20', 'write 20', 'write 10']);
      expect(progress, [(20, 50), (40, 50), (50, 50)]);
      expect(sink.lastValue, List.generate(50, (i) => i));
    });

    test('writes with response in pieces of 512 bytes', () async {
      final peripheral = await connected();
      await sinkOf(peripheral)
          .writeChunked(List.filled(600, 1), withResponse: true);
      expect(served, ['write 512', 'write 88']);
    });

    test('an empty value is one empty write', () async {
      final peripheral = await connected();
      await sinkOf(peripheral).writeChunked(const []);
      expect(served, ['write 0']);
    });

    test('holds the queue until the last piece', () async {
      final peripheral = await connected();
      final sink = sinkOf(peripheral);

      final chunked = sink.writeChunked(List.filled(45, 0));
      final read = sink.read();
      await Future.wait([chunked, read]);

      expect(served, ['write 20', 'write 20', 'write 5', 'read']);
    });

    test('stops sending once cancelled', () async {
      final peripheral = await connected();
      final token = CancelToken();

      await expectLater(
        sinkOf(peripheral).writeChunked(
          List.filled(100, 0),
          onProgress: (_, _) => token.cancel(),
          cancelToken: token,
        ),
        throwsA(isA<OperationCancelledException>()),
      );
      await pumpEventQueue();

      expect(served, ['write 20']);
    });

    test('may take the timeout once per piece', () async {
      final peripheral = await connected();
      final gate = writeGate = Completer();
      final clock = Stopwatch()..start();

      await expectLater(
        sinkOf(peripheral).writeChunked(
          List.filled(40, 0),
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(isA<OperationTimeoutException>()),
      );

      expect(
        clock.elapsed,
        greaterThanOrEqualTo(const Duration(milliseconds: 200)),
      );
      gate.complete();
    });
  });

  group('connect', () {
    test('requests the MTU after connecting', () async {
      install();
      final peripheral = await connected(mtu: 185);
      expect(peripheral.mtu, 185);
      expect(peripheral.maximumWriteLength(withResponse: false), 182);
    });

    test('keeps the connection when the MTU request fails', () async {
      install();
      final peripheral = (await BtKit.instance.peripheral(sensor.id))!;
      bluetooth.failNext(GattError.requestNotSupported);

      await peripheral.connect(mtu: 185);

      expect(peripheral.isConnected, isTrue);
      expect(peripheral.mtu, 23);
    });

    test('leaves the MTU to platforms that negotiate it', () async {
      install(FakeBluetooth.iosCapabilities);
      final peripheral = await connected(mtu: 185);
      expect(peripheral.mtu, 23);
    });

    test('remembers autoConnect', () async {
      install();
      final peripheral = (await BtKit.instance.peripheral(sensor.id))!;
      expect(peripheral.autoConnect, isFalse);
      await peripheral.connect(autoConnect: true);
      expect(peripheral.autoConnect, isTrue);
    });
  });

  test('included services point at the discovered services', () async {
    install();
    final peripheral = await connected();

    final service = peripheral.services.firstWhere(
      (s) => s.uuid == serviceUuid,
    );
    final included = service.includedServices.single;

    expect(included.uuid, batteryUuid);
    expect(included.isPrimary, isFalse);
    expect(included.primaryService, same(service));
    expect(service.primaryService, isNull);
    expect(included, same(peripheral.services.first));
  });

  group('clearGattCache', () {
    test('invalidates the services until they are discovered again', () async {
      install();
      final peripheral = await connected();
      final sink = sinkOf(peripheral);
      var changes = 0;
      peripheral.servicesChanged.listen((_) => changes++);

      expect(await peripheral.clearGattCache(), isTrue);

      expect(sensor.cacheClears, 1);
      expect(peripheral.services, isEmpty);
      await expectLater(
        sink.read(),
        throwsA(isA<AttributeInvalidatedException>()),
      );
      await peripheral.discoverServices();
      expect(await sinkOf(peripheral).read(), [0x00]);
      expect(changes, 0);
    });

    test('is Android only', () async {
      install(FakeBluetooth.iosCapabilities);
      final peripheral = await connected();
      await expectLater(
        peripheral.clearGattCache(),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    });
  });

  group('adapterName', () {
    test('reports the adapter name', () async {
      install();
      bluetooth.adapterName = 'Pixel';
      expect(await BtKit.instance.adapterName(), 'Pixel');
    });

    test('is Android only', () async {
      install(FakeBluetooth.iosCapabilities);
      await expectLater(
        BtKit.instance.adapterName(),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    });
  });
}
