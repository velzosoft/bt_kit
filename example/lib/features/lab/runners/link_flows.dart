import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../central/lab_connection.dart';
import '../model/lab_failure.dart';
import '../profile/database_command.dart';
import '../profile/reference_profile.dart';
import '../profile/stream_command.dart';
import 'flow_steps.dart';

/// App connections, last values, explicit indications, MTU state,
/// connection priority, PHY, Services Changed and disconnect reasons, on one
/// connection to the reference. The last step disconnects.
final class LinkFlows {
  LinkFlows(this.connection, this.steps, this.metrics);

  static const _eventLimit = Duration(seconds: 10);

  final LabConnection connection;
  final FlowSteps steps;
  final Map<String, Object?> metrics;

  BtKit get _bt => BtKit.instance;

  Peripheral get _peripheral => connection.peripheral;

  CancelToken get _cancel => steps.context.cancelToken;

  BluetoothCapabilities get _capabilities => _bt.capabilities;

  Future<void> run() async {
    await steps.step('Listed as connected', _listed);
    await steps.step('Last value', _lastValue);
    await steps.step('Explicit indication', _indication);
    await steps.step('MTU state', _mtu);
    await steps.step('Connection priority', _priority);
    await steps.step('PHY', _phy);
    await steps.step('Services Changed', _servicesChanged);
    await steps.step('Disconnect reason', _disconnectReason);
  }

  Future<String> _listed() async {
    if (!_bt.connectedPeripherals.contains(_peripheral)) {
      throw const UnexpectedResult(
        'BtKit.connectedPeripherals does not list the reference',
      );
    }
    return '${_bt.connectedPeripherals.length} connected';
  }

  Future<String> _lastValue() async {
    final fixed = connection[ReferenceCharacteristic.fixedValue];
    final read = await fixed.read(cancelToken: _cancel);
    ValueMismatch.check('lastValue after a read', fixed.lastValue ?? [], read);

    final echo = connection[ReferenceCharacteristic.echo];
    final changed = echo.valueChanges.first.timeout(_eventLimit);
    const payload = [0x6c, 0x76];
    await echo.write(payload, cancelToken: _cancel);
    ValueMismatch.check(
      'lastValue after a write',
      echo.lastValue ?? [],
      payload,
    );
    ValueMismatch.check('valueChanges after a write', await changed, payload);
    return 'kept after a read and a write';
  }

  /// The indicate stream supports only indications, so asking for them
  /// explicitly works on every platform.
  Future<String> _indication() async {
    final stream = connection.stream(StreamKind.indicate);
    final first = Completer<void>();
    final subscription = stream
        .subscribe(mode: NotifyMode.indication)
        .listen(
          (_) {
            if (!first.isCompleted) first.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!first.isCompleted) first.completeError(error, stackTrace);
          },
        );
    try {
      await connection.startStream(
        StreamKind.indicate,
        10,
        cancelToken: _cancel,
      );
      await first.future.timeout(
        _eventLimit,
        onTimeout: () => throw const DeadlineExceeded('No indication'),
      );
      if (!stream.isNotifying) {
        throw const UnexpectedResult('isNotifying is false while subscribed');
      }
    } finally {
      await connection.stopStream();
      await subscription.cancel();
    }
    await _peripheral.readRssi(cancelToken: _cancel);
    if (stream.isNotifying) {
      throw const UnexpectedResult('isNotifying is true after cancelling');
    }
    return 'on, pushed, then off; lastValue holds the last push';
  }

  Future<String> _mtu() async {
    if (!_capabilities.requestMtu) {
      final expected = _peripheral.maximumWriteLength(withResponse: false) + 3;
      if (_peripheral.mtu != expected) {
        throw UnexpectedResult(
          'mtu is ${_peripheral.mtu}; writes without response allow '
          '${expected - 3} bytes',
        );
      }
      return 'MTU ${_peripheral.mtu}, chosen by the system';
    }
    final mtu = await _peripheral.requestMtu(247, cancelToken: _cancel);
    metrics['mtu'] = mtu;
    if (_peripheral.mtu != mtu) {
      throw UnexpectedResult(
        'requestMtu gave $mtu, but mtu is ${_peripheral.mtu}',
      );
    }
    if (_peripheral.maximumWriteLength(withResponse: false) != mtu - 3) {
      throw const UnexpectedResult(
        'maximumWriteLength does not follow the MTU',
      );
    }
    return 'MTU $mtu';
  }

  Future<String> _priority() async {
    if (!_capabilities.connectionPriority) {
      return _expectUnsupported(
        () => _peripheral.requestConnectionPriority(ConnectionPriority.high),
      );
    }
    await _peripheral.requestConnectionPriority(
      ConnectionPriority.high,
      cancelToken: _cancel,
    );
    await connection[ReferenceCharacteristic.fixedValue].read();
    await _peripheral.requestConnectionPriority(ConnectionPriority.balanced);
    return 'high, then balanced; the link kept working';
  }

  Future<String> _phy() async {
    if (!_capabilities.phy) return _expectUnsupported(_peripheral.readPhy);
    final before = await _peripheral.readPhy(cancelToken: _cancel);
    metrics['phy'] = '$before';
    if (!_capabilities.le2MPhy) return '$before; this phone has no LE 2M PHY';
    final after = await _peripheral.setPreferredPhy(
      tx: {Phy.le2M},
      rx: {Phy.le2M},
      cancelToken: _cancel,
    );
    metrics['phyAfterAskingFor2M'] = '$after';
    final read = await _peripheral.readPhy(cancelToken: _cancel);
    if (read != after) {
      throw UnexpectedResult('setPreferredPhy gave $after, readPhy $read');
    }
    await connection[ReferenceCharacteristic.fixedValue].read();
    return '${before.tx.name}, then ${after.tx.name} after asking for 2M';
  }

  /// The reference adds its extra service, then removes it. The removal
  /// invalidates that service on every platform, so its stale
  /// characteristic must fail.
  Future<String> _servicesChanged() async {
    if (await _databaseHasExtra()) {
      await _changeDatabase(extraService: false);
    }
    await _changeDatabase(extraService: true);
    await _peripheral.discoverServices(cancelToken: _cancel);
    final extra =
        _peripheral.characteristic(
          ReferenceProfile.extraService,
          ReferenceProfile.extraCharacteristic,
        ) ??
        (throw const UnexpectedResult('Rediscovery missed the added service'));
    ValueMismatch.check(
      'Extra value',
      await extra.read(cancelToken: _cancel),
      ReferenceProfile.extraValue,
    );

    await _changeDatabase(extraService: false);
    try {
      await extra.read(cancelToken: _cancel);
      throw const UnexpectedResult('The removed service could still be read');
    } on AttributeInvalidatedException catch (_) {}
    await _peripheral.discoverServices(cancelToken: _cancel);
    if (_peripheral.services.any(
      (s) => s.uuid == ReferenceProfile.extraService,
    )) {
      throw const UnexpectedResult('Rediscovery still finds the removed one');
    }
    return 'added, found, removed; the stale read failed';
  }

  Future<String> _disconnectReason() async {
    final disconnected = _bt.events
        .firstWhere(
          (e) =>
              e is ConnectionChanged &&
              e.peripheral == _peripheral &&
              e.state == BluetoothConnectionState.disconnected,
        )
        .timeout(_eventLimit);
    await _peripheral.disconnect();
    final event = await disconnected as ConnectionChanged;
    final reason = _peripheral.lastDisconnect;
    if (reason?.cause != DisconnectCause.requested ||
        event.reason?.cause != DisconnectCause.requested) {
      throw UnexpectedResult('Reported as $reason, event ${event.reason}');
    }
    if (_bt.connectedPeripherals.contains(_peripheral)) {
      throw const UnexpectedResult('Still listed as connected');
    }
    return 'requested, and no longer listed';
  }

  Future<bool> _databaseHasExtra() async =>
      DatabaseCommand.decode(await _databaseControl.read(cancelToken: _cancel));

  /// Asks the reference to change its database and waits for the
  /// Services Changed that follows.
  Future<void> _changeDatabase({required bool extraService}) async {
    final changed = _peripheral.servicesChanged.first.timeout(
      _eventLimit,
      onTimeout: () => throw DeadlineExceeded(
        'No Services Changed within ${_eventLimit.inSeconds} s of '
        '${extraService ? 'adding' : 'removing'} a service',
      ),
    );
    await _databaseControl.write(
      DatabaseCommand.encode(extraService: extraService),
      cancelToken: _cancel,
    );
    await changed;
  }

  /// Found afresh each time: a Services Changed may invalidate the one
  /// found before.
  GattCharacteristic get _databaseControl =>
      _peripheral.characteristic(
        ReferenceProfile.service,
        ReferenceCharacteristic.databaseControl.uuid,
      ) ??
      (throw const UnexpectedResult('The database control is missing'));

  static Future<String> _expectUnsupported(Future<void> Function() call) async {
    try {
      await call();
    } on UnsupportedFeatureException {
      return 'not offered on this platform, as documented';
    }
    throw const UnexpectedResult('Expected UnsupportedFeatureException');
  }
}
