import '../model/test_result.dart';
import 'memory_trend.dart';

/// What the scan load test measured, and its pass criterion.
///
/// A leaked `ScanResult` with its JNI global reference, or a leaked Dart
/// `Advertisement`, keeps about 1 KB alive per result: 10,000 results would
/// add about 10 MB, growing steadily. A Flutter app's resident memory moves
/// by 1–3 MB with garbage collection alone, so growth under 5 MiB after
/// warm-up separates the two. Quick runs see 2,000 results and only catch
/// leaks above about 2.5 KB per result.
final class ScanLoadMetrics {
  ScanLoadMetrics({required this.target})
    : memory = MemoryTrend(warmup: target ~/ 5);

  static const maxGrowthBytes = 5 * 1024 * 1024;

  final int target;
  final MemoryTrend memory;
  var received = 0;
  var elapsed = Duration.zero;

  /// Why the scan stopped before [target] results, if it did.
  String? stopReason;

  int get sampleEvery => target ~/ 50 < 1 ? 1 : target ~/ 50;

  double get resultsPerSecond => elapsed.inMicroseconds == 0
      ? 0
      : received / (elapsed.inMicroseconds / 1e6);

  List<Check> checks() {
    final growth = memory.growthBytes;
    return [
      Check(
        'Received $target scan results',
        passed: received >= target,
        detail: stopReason ?? '$received received',
      ),
      Check(
        'Memory grew less than ${_mib(maxGrowthBytes)} after warm-up',
        passed: growth != null && growth < maxGrowthBytes,
        detail: growth == null
            ? 'not enough samples'
            : '${_mib(growth)} over ${received - memory.warmup} results',
      ),
    ];
  }

  String get summary {
    final growth = memory.growthBytes;
    return '$received results · ${resultsPerSecond.toStringAsFixed(0)}/s'
        ' · memory ${growth == null ? '…' : _mib(growth)} after warm-up';
  }

  /// [platform] is `Platform.operatingSystem`; JNI references exist on
  /// Android only and cannot be read from inside the app.
  Map<String, Object?> toJson({required String platform}) => {
    'target': target,
    'received': received,
    'seconds': elapsed.inMilliseconds / 1000,
    'resultsPerSecond': resultsPerSecond.round(),
    'warmupResults': memory.warmup,
    'rssGrowthBytes': memory.growthBytes,
    'rssBytesPerResult': memory.bytesPerResult?.round(),
    'rssSamples': [
      for (final s in memory.samples) [s.results, s.bytes],
    ],
    'jniGlobalReferences': platform == 'android'
        ? {
            'before': null,
            'after': null,
            'howToMeasure':
                'Not readable in the app. Run `adb shell dumpsys meminfo '
                'dev.btkit.bt_radar` before and after the test and fill in '
                'before and after.',
          }
        : null,
    if (stopReason != null) 'stopReason': stopReason,
  };

  static String _mib(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
