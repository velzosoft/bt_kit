import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/core/log.dart';
import 'package:bt_kit/src/core/operation_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> subscription;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    subscription = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    BtKit.logLevel = Level.OFF;
    await subscription.cancel();
  });

  test('bt_kit logs nothing by default', () {
    BtLog.gatt.warning(() => 'quiet');
    expect(records, isEmpty);
  });

  test('logLevel lets records through without hierarchical logging', () {
    BtKit.logLevel = Level.FINE;
    BtLog.gatt
      ..fine(() => 'shown')
      ..finer(() => 'payload');
    expect(records.map((r) => (r.loggerName, r.message)), [
      ('bt_kit.gatt', 'shown'),
    ]);
  });

  test('a timeout shows the operation, its queue wait and the native '
      'status of the late answer', () async {
    BtKit.logLevel = Level.FINE;
    final queue = OperationQueue(log: BtLog.gatt, label: 'AA:BB');
    final blocker = Completer<void>();
    final late = Completer<void>();
    unawaited(
      queue.run(
        'discoverServices',
        () => blocker.future,
        timeout: const Duration(seconds: 1),
      ),
    );
    final read = queue.run(
      'read 2a37',
      () => late.future,
      timeout: const Duration(milliseconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    blocker.complete();
    await expectLater(read, throwsA(isA<OperationTimeoutException>()));
    late.completeError(
      GattException(GattError.unknown, 'read', nativeCode: 133),
    );
    await pumpEventQueue();

    final messages = records.map((r) => r.message).toList();
    expect(
      messages,
      contains(
        matches(
          r'^AA:BB: read 2a37 gave up after \d+ ms, having waited \d+ ms '
          r'in the queue: OperationTimeoutException',
        ),
      ),
    );
    expect(
      messages,
      contains(
        allOf(
          startsWith('AA:BB: read 2a37 answered after'),
          contains('native code 133'),
        ),
      ),
    );
  });
}
