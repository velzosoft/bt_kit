import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/central/device_list.dart';
import 'package:bt_kit/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interval = Duration(milliseconds: 500);
  late FakeBluetooth bluetooth;

  setUp(() => bluetooth = FakeBluetooth.install());
  tearDown(FakeBluetooth.uninstall);

  Future<Peripheral> peripheral(String id) async {
    bluetooth.add(FakePeripheral(id: id));
    return (await BtKit.instance.peripheral(id))!;
  }

  void run(
    void Function(
      FakeAsync async,
      StreamController<Advertisement> input,
      List<List<String>> lists,
      Advertisement Function(Peripheral, {int rssi}) ad,
    )
    body, {
    Duration? expireAfter,
  }) {
    fakeAsync((async) {
      final start = DateTime(2026, 11, 25);
      DateTime now() => start.add(async.elapsed);
      final input = StreamController<Advertisement>();
      final lists = <List<String>>[];
      deviceList(
        input.stream,
        interval: interval,
        expireAfter: expireAfter,
        now: now,
      ).listen(
        (list) => lists.add([
          for (final ad in list) '${ad.peripheral.id}@${ad.rssi}',
        ]),
      );
      Advertisement ad(Peripheral peripheral, {int rssi = -50}) =>
          Advertisement(
            peripheral: peripheral,
            rssi: rssi,
            data: const AdvertisementData(),
            receivedAt: now(),
          );
      body(async, input, lists, ad);
    });
  }

  test('keeps the latest advertisement per peripheral in discovery order', () {
    run((async, input, lists, ad) {
      late Peripheral a;
      late Peripheral b;
      peripheral('A').then((p) => a = p);
      peripheral('B').then((p) => b = p);
      async.flushMicrotasks();
      input
        ..add(ad(a, rssi: -70))
        ..add(ad(b, rssi: -60));
      async.elapse(interval);
      input.add(ad(a, rssi: -40));
      async.elapse(interval);
      expect(lists.last, ['A@-40', 'B@-60']);
    });
  });

  test('emits at once, then at most once per interval', () {
    run((async, input, lists, ad) {
      late Peripheral a;
      peripheral('A').then((p) => a = p);
      async.flushMicrotasks();
      input.add(ad(a, rssi: -1));
      async.flushMicrotasks();
      expect(lists, [
        ['A@-1'],
      ]);
      for (var rssi = -2; rssi >= -5; rssi--) {
        input.add(ad(a, rssi: rssi));
        async.elapse(const Duration(milliseconds: 100));
      }
      expect(lists, hasLength(1));
      async.elapse(const Duration(milliseconds: 100));
      expect(lists, [
        ['A@-1'],
        ['A@-5'],
      ]);
      async.elapse(interval * 4);
      expect(lists, hasLength(2));
    });
  });

  test('drops peripherals that stopped advertising', () {
    run(expireAfter: const Duration(seconds: 3), (async, input, lists, ad) {
      late Peripheral a;
      late Peripheral b;
      peripheral('A').then((p) => a = p);
      peripheral('B').then((p) => b = p);
      async.flushMicrotasks();
      input
        ..add(ad(a))
        ..add(ad(b));
      for (var i = 0; i < 8; i++) {
        async.elapse(interval);
        input.add(ad(b));
      }
      expect(lists.last, ['B@-50']);
      async.elapse(const Duration(seconds: 4));
      expect(lists.last, isEmpty);
    });
  });

  test('scanDevices requires duplicates for expiry', () {
    expect(
      () => BtKit.instance.scanDevices(
        const ScanOptions(),
        expireAfter: const Duration(seconds: 5),
      ),
      throwsArgumentError,
    );
  });

  test('scanDevices lists fake peripherals', () async {
    bluetooth
      ..add(FakePeripheral(id: 'A'))
      ..add(FakePeripheral(id: 'B'));
    final list = await BtKit.instance
        .scanDevices(const ScanOptions(), interval: Duration.zero)
        .firstWhere((list) => list.length == 2);
    expect(list.map((ad) => ad.peripheral.id), ['A', 'B']);
  });
}
