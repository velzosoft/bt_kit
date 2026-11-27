import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/core/operation_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late OperationQueue queue;
  const timeout = Duration(milliseconds: 200);

  setUp(() => queue = OperationQueue());

  test('runs operations one at a time, in order', () async {
    final log = <String>[];
    final first = Completer<void>();
    final a = queue.run('a', () async {
      log.add('a start');
      await first.future;
      log.add('a end');
    }, timeout: timeout);
    final b = queue.run('b', () async => log.add('b'), timeout: timeout);
    await pumpEventQueue();
    expect(log, ['a start']);
    first.complete();
    await Future.wait([a, b]);
    expect(log, ['a start', 'a end', 'b']);
  });

  test('a timed-out operation holds the queue until it settles', () async {
    final native = Completer<void>();
    final log = <String>[];
    final slow = queue.run('slow', () => native.future, timeout: timeout);
    final next = queue.run(
      'next',
      () async => log.add('next'),
      timeout: timeout,
    );
    await expectLater(slow, throwsA(isA<OperationTimeoutException>()));
    await pumpEventQueue();
    expect(log, isEmpty);
    native.complete();
    await next;
    expect(log, ['next']);
  });

  test('an operation that never settles releases the queue', () async {
    queue = OperationQueue(settleLimit: timeout);
    final stuck = queue.run(
      'stuck',
      () => Completer<void>().future,
      timeout: timeout,
    );
    final next = queue.run('next', () async => 'ran', timeout: timeout * 3);
    await expectLater(stuck, throwsA(isA<OperationTimeoutException>()));
    expect(await next, 'ran');
  });

  test('cancels an operation that has not started', () async {
    final hold = Completer<void>();
    final token = CancelToken();
    var started = false;
    unawaited(queue.run('hold', () => hold.future, timeout: timeout));
    final waiting = queue.run(
      'waiting',
      () async => started = true,
      timeout: timeout,
      cancelToken: token,
    );
    token.cancel();
    hold.complete();
    await expectLater(waiting, throwsA(isA<OperationCancelledException>()));
    expect(started, isFalse);
  });

  test('a cancelled in-flight operation still holds the queue', () async {
    final native = Completer<void>();
    final token = CancelToken();
    final log = <String>[];
    final inFlight = queue.run(
      'in flight',
      () => native.future,
      timeout: timeout,
      cancelToken: token,
    );
    final next = queue.run(
      'next',
      () async => log.add('next'),
      timeout: timeout,
    );
    await pumpEventQueue();
    token.cancel();
    await expectLater(inFlight, throwsA(isA<OperationCancelledException>()));
    expect(log, isEmpty);
    native.complete();
    await next;
    expect(log, ['next']);
  });

  test('failWaiting fails queued operations only', () async {
    final hold = Completer<String>();
    final running = queue.run('running', () => hold.future, timeout: timeout);
    final queued = queue.run('queued', () async => 'x', timeout: timeout);
    await pumpEventQueue();
    queue.failWaiting(const DisconnectedException());
    await expectLater(queued, throwsA(isA<DisconnectedException>()));
    hold.complete('done');
    expect(await running, 'done');
  });

  test('rejects an already cancelled token synchronously', () {
    final token = CancelToken()..cancel();
    expect(
      () => queue.run('x', () async {}, timeout: timeout, cancelToken: token),
      throwsA(isA<OperationCancelledException>()),
    );
  });
}
