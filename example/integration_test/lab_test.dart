import 'dart:convert';

import 'package:bt_radar/features/lab/central/lab_target.dart';
import 'package:bt_radar/features/lab/model/lab_plan.dart';
import 'package:bt_radar/features/lab/model/lab_test_id.dart';
import 'package:bt_radar/features/lab/model/test_result.dart';
import 'package:bt_radar/features/lab/runners/lab_suite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/bluetooth_setup.dart';

const _full = bool.fromEnvironment('LAB_FULL');
const _pairing = bool.fromEnvironment('LAB_PAIRING');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final plan = LabPlan(
    _full ? LabMode.full : LabMode.quick,
    includePairing: _pairing,
  );
  final suite = LabSuite(plan);
  LabTarget? target;

  setUpAll(() async {
    await prepareBluetooth();
    final reference = await findReference();
    if (reference != null) target = LabTarget(reference);
  });

  for (final id in LabTestId.values) {
    test('${id.title} (${plan.mode.name})', () async {
      if (id.needsReference && target == null) {
        markTestSkipped('No Lab reference peripheral nearby');
        return;
      }
      final report = await suite.run({id}, target: target);
      final result = report.results.single;
      binding.reportData = {
        ...?binding.reportData,
        id.name: result.toJson(),
        'device': report.device,
        'reference': report.reference,
      };
      debugPrint(const JsonEncoder.withIndent('  ').convert(result.toJson()));
      expect(result.outcome, TestOutcome.passed, reason: _why(result));
    }, timeout: Timeout(_timeout(id, plan)));
  }
}

String _why(TestResult result) => [
  result.summary,
  ?result.error,
  for (final check in result.checks)
    if (!check.passed) '${check.name}: ${check.detail}',
].join('\n');

Duration _timeout(LabTestId id, LabPlan plan) => switch (id) {
  LabTestId.notificationSoak => plan.soakDuration + const Duration(minutes: 2),
  LabTestId.scanLoad => plan.scanTimeLimit + const Duration(minutes: 1),
  LabTestId.connectionCycles => Duration(seconds: plan.cycles * 6 + 120),
  LabTestId.cancellation => Duration(seconds: plan.bursts * 10 + 120),
  LabTestId.gattFlows => const Duration(minutes: 3),
  LabTestId.filtersAndLinks => const Duration(minutes: 3),
  LabTestId.platform => const Duration(minutes: 5),
  LabTestId.extras => const Duration(minutes: 3),
};
