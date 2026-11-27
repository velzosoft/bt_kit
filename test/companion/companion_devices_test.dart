import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/companion/companion_devices.dart'
    show createCompanionDevices;
import 'package:bt_kit/src/platform/companion_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/capabilities.dart';

final class FakeCompanionDevice implements CompanionDeviceBackend {
  FakeCompanionDevice(this.id, {this.peripheralId});

  @override
  final String id;

  @override
  final String? peripheralId;

  @override
  String? get name => 'Watch';

  @override
  CompanionHandle get native => throw UnimplementedError();
}

final class FakeCompanion implements CompanionBackend {
  final associated = <FakeCompanionDevice>[];
  final requests = <CompanionRequest>[];
  final observed = <(String, bool)>[];
  final changeEvents = StreamController<CompanionChange>.broadcast();
  Completer<CompanionDeviceBackend?>? picker;

  @override
  Future<CompanionDeviceBackend?> associate(CompanionRequest request) {
    requests.add(request);
    return (picker = Completer()).future;
  }

  @override
  Future<List<CompanionDeviceBackend>> devices() async => associated;

  @override
  Future<void> remove(CompanionDeviceBackend device) async =>
      associated.remove(device);

  @override
  Stream<CompanionChange> get changes => changeEvents.stream;

  @override
  Future<void> observePresence(
    CompanionDeviceBackend device, {
    required bool observe,
  }) async => observed.add((device.id, observe));
}

void main() {
  late FakeCompanion backend;
  late BluetoothCapabilities current;
  late CompanionDevices companion;
  final watch = FakeCompanionDevice('3', peripheralId: 'AA:BB:CC:DD:EE:FF');
  final request = CompanionRequest(
    displayName: 'Watch',
    service: BluetoothUuid.short(0x180d),
  );

  setUp(() {
    backend = FakeCompanion();
    current = capabilities();
    companion = createCompanionDevices(
      backend,
      () => current,
      (_) async => null,
    );
  });

  test('associate returns the device the user chose', () async {
    final associating = companion.associate(request);
    backend.picker!.complete(watch);

    final device = await associating;

    expect(device?.id, '3');
    expect(device?.peripheralId, 'AA:BB:CC:DD:EE:FF');
    expect(backend.requests.single, same(request));
  });

  test('associate returns null when the user dismisses the picker', () async {
    final associating = companion.associate(request);
    backend.picker!.complete(null);

    expect(await associating, isNull);
  });

  test('a cancel token stops waiting for the picker', () async {
    final token = CancelToken();
    final associating = companion.associate(request, cancelToken: token);
    await pumpEventQueue();
    token.cancel();

    await expectLater(associating, throwsA(isA<OperationCancelledException>()));
  });

  test('lists and removes associations', () async {
    backend.associated.add(watch);
    final device = (await companion.devices()).single;

    await companion.remove(device);

    expect(await companion.devices(), isEmpty);
  });

  test('reports changes made outside the app', () async {
    final changes = <CompanionDeviceChange>[];
    companion.changes.listen(changes.add);

    backend.changeEvents.add((
      device: watch,
      kind: CompanionChangeKind.removed,
    ));
    await pumpEventQueue();

    expect(changes.single.device.id, '3');
    expect(changes.single.kind, CompanionChangeKind.removed);
  });

  test('presence is observed per device', () async {
    backend.associated.add(watch);
    final device = (await companion.devices()).single;

    await companion.startObservingPresence(device);
    await companion.stopObservingPresence(device);

    expect(backend.observed, [('3', true), ('3', false)]);
  });

  test('presence needs background delivery', () async {
    backend.associated.add(watch);
    final device = (await companion.devices()).single;
    current = capabilities(backgroundEvents: false);

    expect(
      () => companion.startObservingPresence(device),
      throwsA(isA<UnsupportedFeatureException>()),
    );
  });

  test(
    'without a picker there are no devices and nothing to associate',
    () async {
      current = capabilities(companionDevices: false);

      expect(await companion.devices(), isEmpty);
      await expectLater(
        companion.associate(request),
        throwsA(isA<UnsupportedFeatureException>()),
      );
    },
  );
}
