import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/central/scan_session.dart';
import 'package:bt_kit/src/platform/central_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int starts;
  late int stops;
  late StreamController<ScanHit> native;
  late ScanSessions sessions;

  setUp(() {
    starts = 0;
    stops = 0;
    sessions = ScanSessions((_) {
      native = StreamController<ScanHit>(
        onListen: () => starts++,
        onCancel: () => stops++,
      );
      return native.stream;
    });
  });

  test('listeners with equal options share one native scan', () async {
    final a = sessions.scan(const ScanOptions()).listen((_) {});
    final b = sessions.scan(const ScanOptions()).listen((_) {});
    await pumpEventQueue();
    expect(starts, 1);
    await a.cancel();
    expect(stops, 0);
    await b.cancel();
    expect(stops, 1);
  });

  test('refuses a concurrent scan with different options', () async {
    final a = sessions.scan(const ScanOptions()).listen((_) {});
    expect(
      () => sessions.scan(const ScanOptions(mode: ScanMode.lowLatency)),
      throwsA(isA<ScanException>()),
    );
    await a.cancel();
    expect(
      sessions.scan(const ScanOptions(mode: ScanMode.lowLatency)),
      isA<Stream<ScanHit>>(),
    );
  });

  test('stops the native scan after the timeout', () async {
    final done = Completer<void>();
    sessions
        .scan(const ScanOptions(timeout: Duration(milliseconds: 50)))
        .listen((_) {}, onDone: done.complete);
    await done.future;
    expect(stops, 1);
  });

  ScanHit hit(String id, {String? name}) => (
    peripheral: _Stub(id),
    rssi: -50,
    data: AdvertisementData(localName: name),
    native: null,
  );

  test('checks filters before removing duplicates', () async {
    final names = <String?>[];
    sessions
        .scan(
          const ScanOptions(
            filters: [AdvertisementFilter(nameContains: 'H10')],
          ),
        )
        .listen((hit) => names.add(hit.data.localName));
    await pumpEventQueue();
    native
      ..add(hit('a'))
      ..add(hit('a', name: 'Polar H10'))
      ..add(hit('a', name: 'Polar H10'))
      ..add(hit('b', name: 'Garmin'));
    await pumpEventQueue();
    expect(names, ['Polar H10']);
  });

  test('keeps duplicates when the options allow them', () async {
    var count = 0;
    sessions
        .scan(const ScanOptions(allowDuplicates: true))
        .listen((_) => count++);
    await pumpEventQueue();
    native
      ..add(hit('a'))
      ..add(hit('a'));
    await pumpEventQueue();
    expect(count, 2);
  });

  test('reports the scan state', () async {
    final states = <bool>[];
    sessions.scanningChanges.listen(states.add);
    expect(sessions.isScanning, isFalse);
    const options = ScanOptions(mode: ScanMode.lowLatency);
    final subscription = sessions.scan(options).listen((_) {});
    expect(sessions.isScanning, isTrue);
    expect(sessions.current, options);
    await subscription.cancel();
    await pumpEventQueue();
    expect(sessions.isScanning, isFalse);
    expect(sessions.current, isNull);
    expect(states, [true, false]);
  });
}

final class _Stub implements PeripheralBackend {
  _Stub(this.id);

  @override
  final String id;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
