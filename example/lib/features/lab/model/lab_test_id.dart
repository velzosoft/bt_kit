import 'lab_plan.dart';

enum LabTestId {
  gattFlows('GATT flows'),
  connectionCycles('Connection cycles'),
  notificationSoak('Notification soak'),
  cancellation('Cancellation and timeouts'),
  scanLoad('Scan load'),
  filtersAndLinks('Filters and link features'),
  platform('Platform features'),
  extras('More features');

  const LabTestId(this.title);

  final String title;

  bool get needsReference => this != scanLoad;

  String criterion(LabPlan plan) => switch (this) {
    gattFlows =>
      'Every characteristic of the reference profile behaves as documented',
    connectionCycles =>
      '${plan.cycles} connect, discover, read, write and disconnect cycles; '
          'at least 99.5% succeed',
    notificationSoak =>
      '${plan.soakRateHz} Hz for ${_minutes(plan.soakDuration)}; no lost or '
          'out-of-order values',
    cancellation =>
      '${plan.bursts} bursts of ${plan.burstSize} operations with random '
          'cancellations and 1–30 ms timeouts; the queue never stalls and '
          'requests never overlap',
    scanLoad =>
      '${plan.scanResults} scan results; process memory grows less than '
          '5 MiB after warm-up',
    filtersAndLinks =>
      'Each scan filter finds the reference; last values, explicit '
          'indications, MTU state, connection priority, PHY, Services Changed '
          'and disconnect reasons behave as documented',
    platform =>
      'Bonding, background scans, connection events, distance, audio state '
          'and Classic discovery work where the platform offers them',
    extras =>
      'Scan settings, connecting with an MTU, chunked writes, included '
          'services, GATT cache refresh, the adapter name, advertising '
          'updates and periodic advertising work where the platform offers '
          'them',
  };

  static String _minutes(Duration duration) =>
      duration.inMinutes == 1 ? '1 minute' : '${duration.inMinutes} minutes';
}
