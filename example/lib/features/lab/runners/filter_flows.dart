import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../central/reference_locator.dart';
import '../model/lab_failure.dart';
import '../profile/reference_profile.dart';
import 'flow_steps.dart';

/// Finds the reference with each kind of advertisement filter its
/// advertisement allows. Every scan uses its own options, so the app's
/// shared scan must be paused first.
final class FilterFlows {
  FilterFlows(this.steps, this.notes);

  static const _scanLimit = Duration(seconds: 10);
  static const _idleLimit = Duration(seconds: 2);

  final FlowSteps steps;
  final List<String> notes;

  Future<void> run() async {
    Advertisement? reference;
    await steps.step('Filter by service', () async {
      reference = await _find(
        ScanOptions(services: [ReferenceProfile.service]),
        (ad) => ReferenceLocator.advertises(ad.data),
      );
      return 'found ${reference!.peripheral.id}';
    });
    final found = reference;
    if (found == null) return;
    final id = found.peripheral.id;
    final data = found.data;

    await _filter(
      'Filter by peripheral id',
      id,
      AdvertisementFilter(peripheralId: id),
    );
    if (data.localName case final name?) {
      await _filter('Filter by name', id, AdvertisementFilter(name: name));
      await _filter(
        'Filter by part of the name',
        id,
        AdvertisementFilter(nameContains: name.substring(name.length ~/ 3)),
      );
    } else {
      notes.add('The reference advertises no name; name filters skipped.');
    }
    if (data.manufacturerData.entries.firstOrNull case MapEntry(
      :final key,
      :final value,
    )) {
      await _filter(
        'Filter by manufacturer data',
        id,
        AdvertisementFilter(
          manufacturerId: key,
          manufacturerData: value.take(1).toList(),
          manufacturerDataMask: const [0xff],
        ),
      );
    } else {
      notes.add(
        'The reference advertises no manufacturer data; that filter was '
        'skipped. iOS cannot advertise it.',
      );
    }
    if (data.serviceData.entries.firstOrNull case MapEntry(
      :final key,
      :final value,
    )) {
      await _filter(
        'Filter by service data',
        id,
        AdvertisementFilter(
          serviceData: key,
          serviceDataValue: value.take(1).toList(),
        ),
      );
    } else {
      notes.add(
        'The reference advertises no service data; that filter was skipped. '
        'Phones have no room for it next to the Lab service UUID.',
      );
    }
  }

  Future<void> _filter(String name, String id, AdvertisementFilter filter) =>
      steps.step(name, () async {
        final clock = Stopwatch()..start();
        await _find(
          ScanOptions(filters: [filter]),
          (ad) => ad.peripheral.id == id,
        );
        return 'found in ${clock.elapsedMilliseconds} ms';
      });

  Future<Advertisement> _find(
    ScanOptions options,
    bool Function(Advertisement) wanted,
  ) async {
    await _waitForIdleScan();
    final scan = ScanOptions(
      services: options.services,
      filters: options.filters,
      mode: ScanMode.lowLatency,
      timeout: _scanLimit,
    );
    return BtKit.instance
        .scan(scan)
        .firstWhere(
          wanted,
          orElse: () => throw DeadlineExceeded(
            'Not found within ${_scanLimit.inSeconds} s',
          ),
        );
  }

  /// The paused shared scan ends asynchronously; a scan with other options
  /// is refused until it has.
  static Future<void> _waitForIdleScan() async {
    final bt = BtKit.instance;
    final idle = bt.scanningChanges.firstWhere((scanning) => !scanning);
    if (!bt.isScanning) return;
    await idle.timeout(
      _idleLimit,
      onTimeout: () => throw UnexpectedResult(
        'Another scan is still running: ${bt.currentScan}',
      ),
    );
  }
}
