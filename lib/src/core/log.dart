import 'package:logging/logging.dart';

/// bt_kit's loggers, under `bt_kit`.
///
/// Records below [level] are dropped before they reach `package:logging`,
/// so apps can turn bt_kit's logging on without enabling hierarchical
/// logging. Records then go to `Logger.root.onRecord`, subject to the root
/// logger's level.
final class BtLog {
  BtLog._(String name) : _logger = Logger('bt_kit.$name');

  static final adapter = BtLog._('adapter');
  static final scan = BtLog._('scan');
  static final gatt = BtLog._('gatt');
  static final server = BtLog._('server');
  static final l2cap = BtLog._('l2cap');
  static final bond = BtLog._('bond');
  static final classic = BtLog._('classic');
  static final accessory = BtLog._('accessory');
  static final background = BtLog._('background');
  static final ranging = BtLog._('ranging');
  static final audio = BtLog._('audio');

  static Level level = Level.OFF;

  final Logger _logger;

  bool isLoggable(Level record) => record >= level;

  void warning(String Function() message, [Object? error]) =>
      _log(Level.WARNING, message, error);

  void info(String Function() message) => _log(Level.INFO, message);

  void fine(String Function() message) => _log(Level.FINE, message);

  /// For payload bytes, which can carry personal data.
  void finer(String Function() message) => _log(Level.FINER, message);

  void _log(Level record, String Function() message, [Object? error]) {
    if (isLoggable(record)) _logger.log(record, message, error);
  }
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

String millis(Duration duration) => '${duration.inMilliseconds} ms';
