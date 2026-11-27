import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import 'failure_text.dart';
import 'value_log.dart';

/// What a characteristic or descriptor row shows: the last value, whether
/// an operation is in flight, and how the last one went.
abstract class AttributeController extends ChangeNotifier {
  TimedValue? _value;
  String? _status;
  var _failed = false;
  var _busy = false;
  var _disposed = false;

  TimedValue? get value => _value;

  /// The outcome of the last operation, such as an error or `Wrote 2 bytes`.
  String? get status => _status;

  bool get failed => _failed;

  bool get busy => _busy;

  @protected
  void receive(TimedValue value) {
    _value = value;
    changed();
  }

  @protected
  void report(String? status, {bool failed = false}) {
    _status = status;
    _failed = failed;
    changed();
  }

  /// Runs [operation], one at a time, and reports the status it returns or
  /// the error it throws.
  @protected
  Future<void> perform(Future<String?> Function() operation) async {
    if (_busy) return;
    _busy = true;
    report(null);
    try {
      report(await operation());
    } on BluetoothException catch (e) {
      report(explainFailure(e), failed: true);
    } finally {
      _busy = false;
      changed();
    }
  }

  /// Notifies listeners, unless the controller is already disposed.
  @protected
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class DescriptorController extends AttributeController {
  DescriptorController(this.descriptor);

  final GattDescriptor descriptor;

  Future<void> read() => perform(() async {
    receive(TimedValue(await descriptor.read()));
    return null;
  });
}
