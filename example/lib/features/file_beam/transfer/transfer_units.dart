/// Sizes and rates in binary units, labeled the way phones label them:
/// 1 KB is 1024 bytes.
abstract final class TransferUnits {
  static const kilobyte = 1024;
  static const megabyte = 1024 * 1024;

  /// Such as `512 B`, `12 KB`, `1 MB` or `1.5 MB`.
  static String bytes(int count) => switch (count) {
    < kilobyte => '$count B',
    < megabyte => '${_number(count / kilobyte)} KB',
    _ => '${_number(count / megabyte)} MB',
  };

  /// Kilobytes per second as a bare number, such as `8.5` or `85`.
  static String kilobytesPerSecond(double bytesPerSecond) =>
      _number(bytesPerSecond / kilobyte);

  /// Such as `0.4 s`, `12.3 s` or `1 min 05 s`.
  static String duration(Duration duration) {
    if (duration < const Duration(minutes: 1)) {
      return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
    }
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '${duration.inMinutes} min $seconds s';
  }

  /// One decimal below 10, none from 10 up, and no trailing `.0`.
  static String _number(double value) {
    final text = value < 10 ? value.toStringAsFixed(1) : '${value.round()}';
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}
