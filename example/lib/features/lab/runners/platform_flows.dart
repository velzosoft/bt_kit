import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../model/lab_failure.dart';
import '../profile/reference_profile.dart';
import 'flow_steps.dart';
import 'lab_runner.dart';

/// Each step checks one platform feature against the reference, or records
/// that this platform does not offer it.
final class PlatformFlows {
  PlatformFlows(this.steps, this.metrics);

  static const stepCount = 7;
  static const _eventLimit = Duration(seconds: 30);
  static const _distanceSamples = 5;

  final FlowSteps steps;
  final Map<String, Object?> metrics;

  BtKit get _bt => BtKit.instance;

  BluetoothCapabilities get _capabilities => _bt.capabilities;

  CancelToken get _cancel => steps.context.cancelToken;

  Peripheral get _reference => steps.context.reference.peripheral;

  Future<void> run() async {
    await steps.step('Bond', _bond);
    await steps.step('Background scan', _backgroundScan);
    await steps.step('Connection events', _connectionEvents);
    await steps.step('Distance', _distance);
    await steps.step('Audio profiles', _audio);
    await steps.step('Classic discovery', _discovery);
    await steps.step('Remove bond', _removeBond);
  }

  static const _notOffered = 'Not offered on this platform';

  Future<String> _bond() async {
    if (!_capabilities.bonding) return _notOffered;
    await _reference.createBond(cancelToken: _cancel);
    final bonded = await _bt.bondedPeripherals();
    if (!bonded.contains(_reference)) {
      throw const UnexpectedResult('bondedPeripherals misses the reference');
    }
    return 'bonded; ${bonded.length} bonded peripherals';
  }

  Future<String> _backgroundScan() async {
    if (!_capabilities.backgroundEvents) return _notOffered;
    final found = _bt.backgroundEvents
        .expand(
          (event) => [
            if (event case BackgroundScanResult(:final advertisements))
              ...advertisements,
          ],
        )
        .firstWhere(
          (ad) => ad.data.serviceUuids.contains(ReferenceProfile.service),
        )
        .timeout(_eventLimit);
    final started = DateTime.now();
    await _bt.startBackgroundScan(
      ScanOptions(services: [ReferenceProfile.service]),
    );
    try {
      final advertisement = await found;
      final latency = DateTime.now().difference(started);
      metrics['backgroundScanLatencyMs'] = latency.inMilliseconds;
      return 'found ${advertisement.peripheral.id} after '
          '${latency.inMilliseconds} ms';
    } finally {
      await _bt.stopBackgroundScan();
    }
  }

  /// Connecting the reference is a connection like any other app's, so it
  /// shows up in the system's connection events. The link may still be up
  /// from an earlier step, and then connecting reports nothing: the step
  /// waits for the link to go down and connects once more.
  Future<String> _connectionEvents() async {
    if (!_capabilities.systemConnectionEvents) return _notOffered;
    final events = <SystemConnectionEvent>[];
    bool seen({required bool connected}) =>
        events.any((event) => event.connected == connected);
    final subscription = _bt
        .systemConnections(
          services: [ReferenceProfile.service],
          peripheralIds: [_reference.id],
        )
        .where((event) => event.deviceId == _reference.id)
        .listen(events.add);
    try {
      await _connectAndClose();
      await _until(() => seen(connected: false));
      if (!seen(connected: true)) {
        await _connectAndClose();
        await _until(() => seen(connected: true));
      }
    } finally {
      await subscription.cancel();
    }
    if (!seen(connected: true)) {
      throw const UnexpectedResult('No connection event for the reference');
    }
    if (!seen(connected: false)) {
      throw const UnexpectedResult('No disconnection event for the reference');
    }
    return events.map((e) => e.connected ? 'up' : 'down').join(', ');
  }

  Future<void> _connectAndClose() async {
    final connection = await steps.context.connect();
    await quietly(connection.close);
  }

  /// Waits until [done] holds, for at most [_eventLimit].
  Future<void> _until(bool Function() done) async {
    final clock = Stopwatch()..start();
    while (!done() && clock.elapsed < _eventLimit && !_cancel.isCancelled) {
      await steps.context.pause(const Duration(milliseconds: 200));
    }
  }

  Future<String> _distance() async {
    final method = _capabilities.channelSounding
        ? DistanceMethod.channelSounding
        : _capabilities.rssiRanging
        ? DistanceMethod.rssi
        : null;
    if (method == null) return _notOffered;
    await _bt.requestPermissions(const {BluetoothPermission.ranging});
    final connection = await steps.context.connect();
    try {
      final samples = await _reference
          .measureDistance(method: method)
          .take(_distanceSamples)
          .timeout(_eventLimit)
          .toList();
      final meters = samples.map((s) => s.meters).toList()..sort();
      final median = meters[meters.length ~/ 2];
      metrics['distanceMedianM'] = median;
      return '${method.name}: median ${median.toStringAsFixed(2)} m over '
          '${samples.length} samples';
    } finally {
      await quietly(connection.close);
    }
  }

  Future<String> _audio() async {
    if (!_capabilities.audioProfiles) return _notOffered;
    final connections = await _bt.audio.connections();
    return connections.isEmpty
        ? 'no audio devices connected'
        : connections.map((c) => '${c.profile.name} ${c.deviceId}').join(', ');
  }

  Future<String> _discovery() async {
    if (!_capabilities.classic) return _notOffered;
    final found = await _bt.classic.discover().toList();
    metrics['classicDevices'] = found.length;
    return '${found.length} Classic devices nearby';
  }

  /// Removing a bond needs Android 16; elsewhere it would send the user to
  /// the settings, which a test cannot do.
  Future<String> _removeBond() async {
    if (!_capabilities.bonding) return _notOffered;
    if (!_capabilities.removeBond) {
      return 'Apps cannot remove bonds before Android 16; remove it in the '
          'Bluetooth settings';
    }
    if (!await _reference.removeBond(cancelToken: _cancel)) {
      throw const UnexpectedResult('The bond is still there');
    }
    return 'removed';
  }
}
