import 'dart:collection';
import 'dart:math';

/// Progress and throughput of one transfer.
///
/// The live rate counts the bytes of the last [window], so it ramps up
/// during the first window and falls to zero when the transfer stalls.
final class TransferMonitor {
  TransferMonitor(
    this.total, {
    this.window = const Duration(seconds: 1),
    Duration Function()? clock,
  }) : _clock = clock ?? _stopwatch();

  final int total;
  final Duration window;
  final Duration Function() _clock;
  final _samples = ListQueue<(Duration, int)>();
  var _windowBytes = 0;
  var _transferred = 0;
  var _peak = 0.0;
  Duration? _finishedAfter;

  int get transferred => _transferred;

  bool get isFinished => _finishedAfter != null;

  /// Time since the transfer started, frozen once it finishes.
  Duration get elapsed => _finishedAfter ?? _clock();

  double get progress => total == 0 ? 1 : min(1, _transferred / total);

  /// Bytes per second over the last [window] before now, or before the
  /// transfer finished.
  double get bytesPerSecond {
    _trim(elapsed);
    return _windowRate;
  }

  /// The highest [bytesPerSecond] reached so far.
  double get peakBytesPerSecond => _peak;

  /// Bytes per second over the whole transfer.
  double get averageBytesPerSecond {
    final micros = elapsed.inMicroseconds;
    return micros == 0 ? 0 : _transferred * 1e6 / micros;
  }

  void add(int bytes) {
    final now = _clock();
    _samples.addLast((now, bytes));
    _windowBytes += bytes;
    _transferred += bytes;
    _trim(now);
    _peak = max(_peak, _windowRate);
  }

  void finish() => _finishedAfter ??= _clock();

  double get _windowRate => _windowBytes * 1e6 / window.inMicroseconds;

  void _trim(Duration now) {
    while (_samples.isNotEmpty && now - _samples.first.$1 >= window) {
      _windowBytes -= _samples.removeFirst().$2;
    }
  }

  static Duration Function() _stopwatch() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}
