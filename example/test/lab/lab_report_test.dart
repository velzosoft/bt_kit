import 'dart:convert';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/lab/model/failure_tally.dart';
import 'package:bt_radar/features/lab/model/lab_failure.dart';
import 'package:bt_radar/features/lab/model/lab_plan.dart';
import 'package:bt_radar/features/lab/model/lab_report.dart';
import 'package:bt_radar/features/lab/model/lab_test_id.dart';
import 'package:bt_radar/features/lab/model/test_result.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 11, 25, 14, 30, 5);

TestResult result(
  LabTestId id, {
  List<bool> checks = const [true],
  bool cancelled = false,
  String? error,
}) => TestResult(
  id: id,
  criterion: id.criterion(LabPlan(LabMode.full)),
  startedAt: _start,
  finishedAt: _start.add(const Duration(seconds: 90)),
  summary: 'summary',
  checks: [
    for (final (i, passed) in checks.indexed)
      Check('check $i', passed: passed, detail: 'detail'),
  ],
  metrics: const {'value': 1},
  cancelled: cancelled,
  error: error,
);

void main() {
  group('TestResult outcome', () {
    test('passes when every check passes', () {
      expect(result(LabTestId.scanLoad).outcome, TestOutcome.passed);
    });

    test('fails when any check fails, or there are none', () {
      expect(
        result(LabTestId.scanLoad, checks: [true, false]).outcome,
        TestOutcome.failed,
      );
      expect(
        result(LabTestId.scanLoad, checks: []).outcome,
        TestOutcome.failed,
      );
    });

    test('cancelled and error take precedence', () {
      expect(
        result(LabTestId.scanLoad, cancelled: true).outcome,
        TestOutcome.cancelled,
      );
      expect(
        result(LabTestId.scanLoad, error: 'no Bluetooth').outcome,
        TestOutcome.error,
      );
    });
  });

  group('LabReport', () {
    LabReport report(List<TestResult> results) => LabReport(
      plan: LabPlan(LabMode.full),
      startedAt: _start,
      finishedAt: _start.add(const Duration(minutes: 30)),
      device: const {'platform': 'android', 'sdkInt': 36},
      reference: const {'info': 'iOS 26.1.0'},
      results: results,
    );

    test('encodes everything a run measured as JSON', () {
      final json = jsonDecode(
        report([
          result(LabTestId.connectionCycles),
          result(LabTestId.scanLoad, checks: [false]),
        ]).encode(),
      ) as Map<String, Object?>;
      expect(json['schema'], 'bt_kit.lab/1');
      expect(json['startedAt'], '2026-11-25T14:30:05.000Z');
      expect(json['device'], {'platform': 'android', 'sdkInt': 36});
      expect(json['reference'], {'info': 'iOS 26.1.0'});
      expect((json['plan']! as Map)['cycles'], 500);
      expect(json['summary'], {
        'allPassed': false,
        'passed': 1,
        'failed': 1,
        'cancelled': 0,
        'error': 0,
      });
      final first = (json['results']! as List).first as Map<String, Object?>;
      expect(first['id'], 'connectionCycles');
      expect(first['outcome'], 'passed');
      expect(first['durationSeconds'], 90);
      expect(first['criterion'], contains('99.5%'));
      expect(first['checks'], [
        {'name': 'check 0', 'passed': true, 'detail': 'detail'},
      ]);
    });

    test('passes only when every result passes', () {
      expect(report([result(LabTestId.gattFlows)]).passed, isTrue);
      expect(report([]).passed, isFalse);
    });

    test('names its file after the mode and start time', () {
      expect(report([]).fileName, 'bt_kit-lab-full-20261125-143005.json');
    });
  });

  group('LabPlan', () {
    test('full runs use the full pass criteria', () {
      final plan = LabPlan(LabMode.full);
      expect(plan.cycles, 500);
      expect(plan.soakDuration, const Duration(minutes: 10));
      expect(plan.soakRateHz, 50);
      expect(plan.scanResults, 10000);
    });

    test('quick runs are smoke tests', () {
      final plan = LabPlan(LabMode.quick, includePairing: true);
      expect(plan.cycles, 50);
      expect(plan.soakDuration, const Duration(minutes: 1));
      expect(plan.scanResults, 2000);
      expect(plan.includePairing, isTrue);
    });
  });

  group('FailureTally', () {
    test('names Bluetooth and Lab failures', () {
      expect(
        FailureTally.nameOf(GattException(GattError.readNotPermitted, 'read')),
        'GattException(readNotPermitted)',
      );
      expect(
        FailureTally.nameOf(const DisconnectedException()),
        'DisconnectedException',
      );
      expect(
        FailureTally.nameOf(ValueMismatch('Echo', [1], [2])),
        'ValueMismatch',
      );
    });

    test('describes native codes', () {
      expect(
        FailureTally.describe(
          const ConnectionException('Connection failed', nativeCode: 133),
        ),
        'ConnectionException: Connection failed (native code 133)',
      );
    });

    test('keeps at most 20 samples', () {
      final tally = FailureTally();
      for (var i = 0; i < 25; i++) {
        tally.add('read', const DisconnectedException(), context: '#$i');
      }
      expect(tally.count, 25);
      expect(tally.samples, hasLength(FailureTally.maxSamples));
      expect(tally.samples.first, startsWith('#0 read: DisconnectedException'));
    });
  });
}
