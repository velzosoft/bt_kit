import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/bluetooth/reconnector.dart';
import 'package:flutter_test/flutter_test.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

void main() {
  group('Backoff', () {
    test('waits 1, 2, 5, then 10 s repeating', () {
      const backoff = Backoff();
      expect(
        [for (var i = 0; i < 7; i++) backoff.delay(i)],
        [_s(1), _s(2), _s(5), _s(10), _s(10), _s(10), _s(10)],
      );
    });
  });

  group('Reconnector', () {
    late List<Duration> slept;

    Future<void> fakeSleep(Duration delay, CancelToken _) async =>
        slept.add(delay);

    setUp(() => slept = []);

    test('retries Bluetooth failures with backoff', () async {
      var sessions = 0;
      late final Reconnector reconnector;
      reconnector = Reconnector((_) async {
        if (++sessions == 6) return reconnector.cancel();
        throw const DisconnectedException();
      }, sleep: fakeSleep);

      await reconnector.run();

      expect(sessions, 6);
      expect(slept, [_s(1), _s(2), _s(5), _s(10), _s(10)]);
    });

    test('retries a session that ends without an error', () async {
      var sessions = 0;
      late final Reconnector reconnector;
      reconnector = Reconnector((_) async {
        if (++sessions == 3) reconnector.cancel();
      }, sleep: fakeSleep);

      await reconnector.run();

      expect(sessions, 3);
      expect(slept, [_s(1), _s(2)]);
    });

    test('starts from the shortest delay after a working session', () async {
      var sessions = 0;
      late final Reconnector reconnector;
      reconnector = Reconnector((_) async {
        sessions++;
        if (sessions == 4) reconnector.resetBackoff();
        if (sessions == 6) return reconnector.cancel();
        throw const DisconnectedException();
      }, sleep: fakeSleep);

      await reconnector.run();

      expect(slept, [_s(1), _s(2), _s(5), _s(1), _s(2)]);
    });

    test('reports each retry with the error that caused it', () async {
      final retries = <(BluetoothException?, Duration)>[];
      var sessions = 0;
      late final Reconnector reconnector;
      reconnector = Reconnector(
        (_) async {
          switch (++sessions) {
            case 1:
              throw const DisconnectedException();
            case 2:
              return;
            default:
              reconnector.cancel();
          }
        },
        sleep: fakeSleep,
        onRetry: (error, delay) => retries.add((error, delay)),
      );

      await reconnector.run();

      expect(retries, hasLength(2));
      expect(retries[0].$1, isA<DisconnectedException>());
      expect(retries[0].$2, _s(1));
      expect(retries[1].$1, isNull);
      expect(retries[1].$2, _s(2));
    });

    test('never runs two sessions at once', () async {
      var active = 0;
      var mostActive = 0;
      var sessions = 0;
      late final Reconnector reconnector;
      reconnector = Reconnector((_) async {
        active++;
        mostActive = mostActive > active ? mostActive : active;
        await Future<void>.delayed(Duration.zero);
        active--;
        if (++sessions == 5) return reconnector.cancel();
        throw const DisconnectedException();
      }, sleep: fakeSleep);

      final first = reconnector.run();
      final second = reconnector.run();
      await first;

      expect(identical(first, second), isTrue);
      expect(sessions, 5);
      expect(mostActive, 1);
    });

    test('stops when cancelled during a session', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var sessions = 0;
      final reconnector = Reconnector((token) async {
        sessions++;
        started.complete();
        await release.future;
        token.throwIfCancelled();
      }, sleep: fakeSleep);

      final running = reconnector.run();
      await started.future;
      reconnector.cancel();
      release.complete();
      await running;

      expect(sessions, 1);
      expect(slept, isEmpty);
    });

    test('stops when cancelled while waiting', () async {
      var sessions = 0;
      final reconnector = Reconnector((_) async {
        sessions++;
        throw const DisconnectedException();
      }, backoff: const Backoff([Duration(hours: 1)]));

      final running = reconnector.run();
      await Future<void>.delayed(Duration.zero);
      reconnector.cancel();
      await running.timeout(const Duration(seconds: 1));

      expect(sessions, 1);
    });

    test('ends with errors that are not Bluetooth failures', () async {
      final reconnector = Reconnector(
        (_) async => throw StateError('bug'),
        sleep: fakeSleep,
      );

      await expectLater(reconnector.run(), throwsStateError);
      expect(slept, isEmpty);
    });
  });

  group('cancellableSleep', () {
    test('waits for the delay', () async {
      final watch = Stopwatch()..start();
      await cancellableSleep(const Duration(milliseconds: 20), CancelToken());
      expect(watch.elapsed, greaterThanOrEqualTo(_ms(15)));
    });

    test('returns early when cancelled', () async {
      final token = CancelToken();
      final sleeping = cancellableSleep(const Duration(hours: 1), token);
      token.cancel();
      await sleeping.timeout(const Duration(seconds: 1));
    });

    test('returns at once when already cancelled', () async {
      final token = CancelToken()..cancel();
      await cancellableSleep(
        const Duration(hours: 1),
        token,
      ).timeout(const Duration(seconds: 1));
    });
  });
}

Duration _ms(int milliseconds) => Duration(milliseconds: milliseconds);
