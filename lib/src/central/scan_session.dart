import 'dart:async';

import '../core/exceptions.dart';
import '../core/log.dart';
import '../models/scan_options.dart';
import '../platform/central_backend.dart';

/// Shares one native scan between every listener that asks for the same
/// [ScanOptions].
///
/// Both platforms run a single scan per app: iOS replaces the running scan
/// when a new one starts, and Android throttles apps that restart scans
/// often. A second scan with different options is therefore refused rather
/// than silently changing the first.
///
/// Every result is checked against the options' filters, whatever the
/// platform already filtered, and duplicates are removed here unless the
/// options allow them.
final class ScanSessions {
  ScanSessions(this._start);

  final Stream<ScanHit> Function(ScanOptions) _start;
  final _scanning = StreamController<bool>.broadcast();
  _Session? _active;

  /// The options of the scan in progress.
  ScanOptions? get current => _active?.options;

  bool get isScanning => _active != null;

  Stream<bool> get scanningChanges => _scanning.stream;

  Stream<ScanHit> scan(ScanOptions options) {
    final active = _active;
    if (active != null && active.options != options) {
      throw const ScanException(
        'A scan with different options is already running. Cancel it first.',
      );
    }
    if (active != null) return active.stream;
    final session = _active = _Session(options, _start, _ended);
    BtLog.scan.info(() => 'Scan started: $options');
    _scanning.add(true);
    return session.stream;
  }

  void _ended(_Session session) {
    if (!identical(_active, session)) return;
    _active = null;
    BtLog.scan.info(() => 'Scan stopped');
    _scanning.add(false);
  }
}

final class _Session {
  _Session(this.options, this._start, this._onEnd);

  final ScanOptions options;
  final Stream<ScanHit> Function(ScanOptions) _start;
  final void Function(_Session) _onEnd;
  late final _controller = StreamController<ScanHit>.broadcast(
    onListen: _listen,
    onCancel: _end,
  );
  final _reported = <String>{};
  StreamSubscription<ScanHit>? _source;
  Timer? _timeout;

  Stream<ScanHit> get stream => _controller.stream;

  void _listen() {
    _source = _start(options)
        .listen(_deliver, onError: _controller.addError, onDone: _end);
    final timeout = options.timeout;
    if (timeout != null) _timeout = Timer(timeout, _end);
  }

  void _deliver(ScanHit hit) {
    final id = hit.peripheral.id;
    if (!options.matches(id, hit.data)) return;
    if (options.allowDuplicates || _reported.add(id)) _controller.add(hit);
  }

  Future<void> _end() async {
    _onEnd(this);
    _timeout?.cancel();
    final source = _source;
    _source = null;
    await source?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }
}
