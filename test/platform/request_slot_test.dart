import 'package:bt_kit/bt_kit.dart';
import 'package:bt_kit/src/platform/request_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RequestSlot slot;

  setUp(() => slot = RequestSlot());

  test('completes the matching request', () async {
    final read = slot.begin<int>('read', key: 7);
    expect(slot.complete('read', 42, key: 7), isTrue);
    expect(await read.future, 42);
    expect(read.isPending, isFalse);
    expect(slot.isBusy, isFalse);
  });

  test('ignores callbacks for another kind or key', () async {
    final read = slot.begin<int>('read', key: 7);
    expect(slot.complete('write', null), isFalse);
    expect(slot.complete('read', 1, key: 8), isFalse);
    expect(slot.isBusy, isTrue);
    slot.complete('read', 2, key: 7);
    expect(await read.future, 2);
  });

  test('ignores late callbacks once nothing is pending', () {
    expect(slot.complete('read', 1), isFalse);
  });

  test('failAny fails the pending request', () async {
    final rssi = slot.begin<int>('rssi');
    slot.failAny(const DisconnectedException());
    await expectLater(rssi.future, throwsA(isA<DisconnectedException>()));
    expect(slot.isBusy, isFalse);
  });

  test('a new request supersedes the pending one', () async {
    final first = slot.begin<void>('write', key: 1);
    final second = slot.begin<void>('write', key: 1);
    await expectLater(first.future, throwsA(isA<NativeOperationException>()));
    expect(first.isPending, isFalse);
    expect(second.isPending, isTrue);
  });

  test('a request fails only itself, never a newer one', () async {
    final first = slot.begin<void>('write', key: 1);
    final firstFailed = expectLater(
      first.future,
      throwsA(isA<NativeOperationException>()),
    );
    final second = slot.begin<void>('write', key: 1);
    await firstFailed;
    first.fail(const NativeOperationException('rejected'));
    expect(second.isPending, isTrue);
    slot.complete('write', null, key: 1);
    await second.future;
  });
}
