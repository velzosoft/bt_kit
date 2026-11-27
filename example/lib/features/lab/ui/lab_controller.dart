import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../../bluetooth/scanner.dart';
import '../../../bluetooth/tracked_device.dart';
import '../central/lab_target.dart';
import '../central/reference_locator.dart';
import '../model/lab_plan.dart';
import '../model/lab_report.dart';
import '../model/lab_test_id.dart';
import '../model/test_progress.dart';
import '../model/test_result.dart';
import '../runners/lab_suite.dart';

/// The Lab's run tab: which tests to run against which reference, and
/// their live progress and results.
final class LabController extends ChangeNotifier {
  LabController(this.scanner);

  final Scanner scanner;
  final selected = {...LabTestId.values};
  final progress = <LabTestId, TestProgress>{};
  final results = <LabTestId, TestResult>{};
  var mode = LabMode.quick;
  var includePairing = false;
  LabTestId? running;
  LabReport? report;
  String? _targetId;
  CancelToken? _cancelToken;
  CancelToken? _skipToken;
  var _disposed = false;

  bool get isRunning => _cancelToken != null;

  bool get isCancelling => _cancelToken?.isCancelled ?? false;

  bool get isSkipping => _skipToken?.isCancelled ?? false;

  LabPlan get plan => LabPlan(mode, includePairing: includePairing);

  /// Reference peripherals the shared scan hears, strongest first.
  List<TrackedDevice> get references => [
    for (final device in scanner.bySignal)
      if (ReferenceLocator.advertises(device.data)) device,
  ];

  TrackedDevice? get target {
    final references = this.references;
    for (final device in references) {
      if (device.id == _targetId) return device;
    }
    return references.firstOrNull;
  }

  bool get needsReference => selected.any((id) => id.needsReference);

  bool get canRun =>
      !isRunning && selected.isNotEmpty && (!needsReference || target != null);

  void choose(TrackedDevice device) => _update(() => _targetId = device.id);

  void setMode(LabMode mode) => _update(() => this.mode = mode);

  void setIncludePairing(bool value) => _update(() => includePairing = value);

  void toggle(LabTestId id, {required bool on}) =>
      _update(() => on ? selected.add(id) : selected.remove(id));

  Future<void> run() async {
    if (!canRun) return;
    final cancelToken = _cancelToken = CancelToken();
    final target = needsReference ? LabTarget(this.target!.peripheral) : null;
    progress.clear();
    results.clear();
    report = null;
    _changed();
    try {
      report = await LabSuite(plan, scanner: scanner).run(
        {...selected},
        target: target,
        cancelToken: cancelToken,
        onStart: (id, skip) => _update(() {
          running = id;
          _skipToken = skip;
        }),
        onProgress: (id, p) => _update(() => progress[id] = p),
        onResult: (result) => _update(() => results[result.id] = result),
      );
    } finally {
      running = null;
      _cancelToken = null;
      _skipToken = null;
      _changed();
    }
  }

  /// Cancels the running test and moves on to the next.
  void skip() {
    _skipToken?.cancel('Skipped in the Lab');
    _changed();
  }

  void cancel() {
    _cancelToken?.cancel('Cancelled in the Lab');
    _changed();
  }

  void _update(void Function() change) {
    change();
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel('The Lab closed');
    super.dispose();
  }
}
