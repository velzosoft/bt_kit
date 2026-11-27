import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/peripheral_role/gatt_server.dart'
    show createGattServer;
import 'package:bt_kit/src/platform/peripheral_role_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  final serviceUuid = BluetoothUuid.short(0x180d);
  late FakeServerBackend backend;
  late GattServer server;
  late LocalCharacteristic static;
  late LocalCharacteristic notifying;
  late LocalCharacteristic secret;
  final alice = FakeCentral('alice');
  final bob = FakeCentral('bob', maximumUpdateLength: 2);

  setUp(() async {
    backend = FakeServerBackend();
    server = createGattServer(backend);
    static = LocalCharacteristic(
      BluetoothUuid.short(0x2a29),
      properties: const CharacteristicProperties.of(read: true, write: true),
      value: [1, 2, 3, 4, 5, 6],
    );
    notifying = LocalCharacteristic(
      BluetoothUuid.short(0x2a37),
      properties: const CharacteristicProperties.of(read: true, notify: true),
    );
    secret = LocalCharacteristic(
      BluetoothUuid.short(0x2a38),
      properties: const CharacteristicProperties.of(write: true),
    );
    await server.addService(
      LocalService(serviceUuid, [static, notifying, secret]),
    );
  });

  group('reads', () {
    test('serve the stored value', () async {
      expectValue(await backend.read(alice, static), [1, 2, 3, 4, 5, 6]);
    });

    test('serve long reads from a snapshot taken at offset 0', () async {
      await backend.read(alice, static);
      server.setValue(static, [9, 9]);
      expectValue(await backend.read(alice, static, offset: 4), [5, 6]);
      expectValue(await backend.read(alice, static), [9, 9]);
    });

    test('call the read handler once per read', () async {
      var calls = 0;
      final counter = LocalCharacteristic(
        BluetoothUuid.short(0x2a19),
        properties: const CharacteristicProperties.of(read: true),
        onRead: (request) => [++calls, request.central.id.length],
      );
      await server.addService(LocalService(serviceUuid, [counter]));
      expectValue(await backend.read(alice, counter), [1, 5]);
      expectValue(await backend.read(alice, counter, offset: 1), [5]);
      expect(calls, 1);
    });

    test('answer handler failures with ATT errors', () async {
      final failing = LocalCharacteristic(
        BluetoothUuid.short(0x2a19),
        properties: const CharacteristicProperties.of(read: true),
        onRead: (_) =>
            throw GattException(GattError.insufficientAuthorization, 'read'),
      );
      final crashing = LocalCharacteristic(
        BluetoothUuid.short(0x2a1a),
        properties: const CharacteristicProperties.of(read: true),
        onRead: (_) => throw StateError('bug'),
      );
      await server.addService(LocalService(serviceUuid, [failing, crashing]));
      expect(await backend.read(alice, failing), (
        GattError.insufficientAuthorization,
        null,
      ));
      expect(await backend.read(alice, crashing), (
        GattError.unlikelyError,
        null,
      ));
    });

    test('time out slow handlers', () async {
      server.requestTimeout = const Duration(milliseconds: 20);
      final slow = LocalCharacteristic(
        BluetoothUuid.short(0x2a19),
        properties: const CharacteristicProperties.of(read: true),
        onRead: (_) => Completer<List<int>>().future,
      );
      await server.addService(LocalService(serviceUuid, [slow]));
      expect(await backend.read(alice, slow), (GattError.unlikelyError, null));
    });

    test('reject unreadable attributes and bad offsets', () async {
      expect(await backend.read(alice, secret), (
        GattError.readNotPermitted,
        null,
      ));
      expect(await backend.read(alice, static, offset: 7), (
        GattError.invalidOffset,
        null,
      ));
      final unknown = LocalCharacteristic(
        BluetoothUuid.short(0x2a00),
        properties: const CharacteristicProperties.of(read: true),
      );
      expect(await backend.read(alice, unknown), (
        GattError.invalidHandle,
        null,
      ));
    });
  });

  group('writes', () {
    test('store the value when there is no handler', () async {
      expect(
        await backend.write(alice, [
          (static, 0, [7]),
        ]),
        isNull,
      );
      expect(server.value(static), [7]);
    });

    test('apply an offset onto the current value', () async {
      await backend.write(alice, [
        (static, 2, [0, 0]),
      ]);
      expect(server.value(static), [1, 2, 0, 0]);
    });

    test('keep the value when the handler rejects it', () async {
      final guarded = LocalCharacteristic(
        BluetoothUuid.short(0x2a39),
        properties: const CharacteristicProperties.of(write: true),
        value: [1],
        onWrite: (request) {
          if (request.value.first > 9) {
            throw GattException(GattError.valueNotAllowed, 'write');
          }
        },
      );
      await server.addService(LocalService(serviceUuid, [guarded]));
      expect(
        await backend.write(alice, [
          (guarded, 0, [10]),
        ]),
        GattError.valueNotAllowed,
      );
      expect(server.value(guarded), [1]);
    });

    test('reject a whole queue when one write is invalid', () async {
      final error = await backend.write(alice, [
        (static, 0, [8]),
        (notifying, 0, [8]),
      ]);
      expect(error, GattError.writeNotPermitted);
      expect(server.value(static), [1, 2, 3, 4, 5, 6]);
    });
  });

  group('subscriptions and notifications', () {
    void subscribe(Central central, {bool subscribed = true}) => backend.emit(
      SubscriptionChanged(
        central,
        backend.keys[notifying]!,
        subscribed: subscribed,
      ),
    );

    test('track subscribers and report changes', () async {
      final changes = <bool>[];
      server.subscriptionChanges.listen((c) => changes.add(c.subscribed));
      subscribe(alice);
      subscribe(alice, subscribed: false);
      await pumpEventQueue();
      expect(changes, [true, false]);
      expect(server.subscribers(notifying), isEmpty);
    });

    test('notify only subscribed centrals and store the value', () async {
      subscribe(alice);
      await pumpEventQueue();
      await server.notify(notifying, [42]);
      expect(backend.notifications.single.$3, 'alice');
      expect(server.value(notifying), [42]);
    });

    test('limit notifications to the given centrals', () async {
      subscribe(alice);
      subscribe(bob);
      await pumpEventQueue();
      await server.notify(notifying, [1], centrals: [bob]);
      expect(backend.notifications.map((n) => n.$3), ['bob']);
    });

    test('refuse values longer than a central accepts', () async {
      subscribe(bob);
      await pumpEventQueue();
      expect(
        () => server.notify(notifying, [1, 2, 3]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('send one notification per central at a time', () async {
      subscribe(alice);
      await pumpEventQueue();
      backend.notificationGate = Completer();
      final first = server.notify(notifying, [1]);
      final second = server.notify(notifying, [2]);
      await pumpEventQueue();
      expect(backend.notifications, hasLength(1));
      backend.notificationGate!.complete();
      await Future.wait([first, second]);
      expect(backend.notifications.map((n) => n.$2), [
        [1],
        [2],
      ]);
    });

    test('forget a central that disconnects', () async {
      subscribe(alice);
      await pumpEventQueue();
      backend.emit(CentralDisconnected(alice));
      await pumpEventQueue();
      expect(server.subscribers(notifying), isEmpty);
      expect(server.centrals, isEmpty);
    });
  });

  group('included services', () {
    test('are passed to the platform with the service', () async {
      final secondary = LocalService(
        BluetoothUuid.short(0x180f),
        const [],
        isPrimary: false,
      );
      final primary = LocalService(
        BluetoothUuid.short(0x1810),
        const [],
        includedServices: [secondary],
      );

      await Future.wait([
        server.addService(secondary),
        server.addService(primary),
      ]);

      expect(backend.included[primary], [secondary]);
    });

    test('must be added first', () async {
      final primary = LocalService(
        BluetoothUuid.short(0x1810),
        const [],
        includedServices: [LocalService(BluetoothUuid.short(0x180f), const [])],
      );
      await expectLater(server.addService(primary), throwsArgumentError);
      expect(server.services, isNot(contains(primary)));
    });
  });

  test('asks a central for a connection priority', () async {
    await server.requestConnectionPriority(alice, ConnectionPriority.high);
    expect(backend.priorities, [('alice', ConnectionPriority.high)]);
  });

  test('close stops the server', () async {
    await server.close();
    expect(backend.closed, isTrue);
    expect(() => server.notify(notifying, [1]), throwsStateError);
  });

  test('assembleWrites joins the pieces of a long write', () {
    final writes = assembleWrites([
      (key: 1, offset: 0, value: Uint8List.fromList([1, 2])),
      (key: 2, offset: 0, value: Uint8List.fromList([9])),
      (key: 1, offset: 2, value: Uint8List.fromList([3])),
    ]);
    expect(writes.map((w) => (w.key, w.offset)), [(1, 0), (2, 0)]);
    expect(writes.map((w) => w.value), [
      [1, 2, 3],
      [9],
    ]);
  });
}

void expectValue((GattError?, Uint8List?) response, List<int> value) {
  expect(response.$1, isNull);
  expect(response.$2, value);
}
