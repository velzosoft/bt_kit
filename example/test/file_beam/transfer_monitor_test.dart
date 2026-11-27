import 'package:bt_radar/features/file_beam/transfer/transfer_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var now = Duration.zero;
  TransferMonitor monitor(int total) =>
      TransferMonitor(total, clock: () => now);

  setUp(() => now = Duration.zero);

  void at(int milliseconds) => now = Duration(milliseconds: milliseconds);

  test('tracks progress', () {
    final transfer = monitor(4096)..add(1024);
    expect(transfer.transferred, 1024);
    expect(transfer.progress, 0.25);
  });

  test('an empty transfer is complete', () {
    expect(monitor(0).progress, 1);
  });

  test('the rate counts the bytes of the last second', () {
    final transfer = monitor(10000);
    at(100);
    transfer.add(1024);
    at(500);
    transfer.add(1024);
    at(900);
    expect(transfer.bytesPerSecond, 2048);
    at(1200);
    expect(transfer.bytesPerSecond, 1024);
    at(1600);
    expect(transfer.bytesPerSecond, 0);
  });

  test('remembers the peak rate', () {
    final transfer = monitor(10000);
    for (final ms in [0, 100, 200]) {
      at(ms);
      transfer.add(1000);
    }
    at(2000);
    transfer.add(500);
    expect(transfer.bytesPerSecond, 500);
    expect(transfer.peakBytesPerSecond, 3000);
  });

  test('freezes the elapsed time when finished', () {
    final transfer = monitor(2048);
    at(1000);
    transfer.add(2048);
    at(2000);
    transfer.finish();
    at(5000);
    expect(transfer.isFinished, isTrue);
    expect(transfer.elapsed, const Duration(seconds: 2));
    expect(transfer.averageBytesPerSecond, 1024);
  });

  test('the average is zero before any time passes', () {
    expect(monitor(10).averageBytesPerSecond, 0);
  });
}
