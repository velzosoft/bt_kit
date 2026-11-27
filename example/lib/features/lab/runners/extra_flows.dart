import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import '../central/lab_connection.dart';
import '../model/lab_failure.dart';
import '../profile/reference_profile.dart';
import 'flow_steps.dart';
import 'lab_runner.dart';

/// Each step checks one feature against the reference, or on this phone
/// alone, or records that this platform does not offer it.
final class ExtraFlows {
  ExtraFlows(this.steps, this.metrics);

  static const stepCount = 8;
  static const _scanLimit = Duration(seconds: 15);
  static const _mtu = 247;
  static const _defaultMtu = 23;
  static const _notOffered = 'Not offered on this platform';

  final FlowSteps steps;
  final Map<String, Object?> metrics;

  BtKit get _bt => BtKit.instance;

  BluetoothCapabilities get _capabilities => _bt.capabilities;

  CancelToken get _cancel => steps.context.cancelToken;

  Future<void> run() async {
    await steps.step('Scan settings', _scanSettings);
    await steps.step('Connect with an MTU', _connectWithMtu);
    await steps.step('Chunked write', _chunkedWrite);
    await steps.step('Included service', _includedService);
    await steps.step('GATT cache refresh', _cacheRefresh);
    await steps.step('Adapter name', _adapterName);
    await steps.step('Advertising update', _advertisingUpdate);
    await steps.step('Periodic advertising', _periodicAdvertising);
  }

  /// The reference advertises legacy advertisements, which are sent on
  /// LE 1M.
  Future<String> _scanSettings() async {
    final found = await _bt
        .scan(
          ScanOptions(
            services: [ReferenceProfile.service],
            legacyOnly: true,
            phy: ScanPhy.le1M,
          ),
        )
        .first
        .timeout(_scanLimit);
    return 'a legacy scan on LE 1M found ${found.peripheral.id}';
  }

  Future<String> _connectWithMtu() => _connected((connection) async {
    final mtu = connection.peripheral.mtu;
    metrics['connectMtu'] = mtu;
    if (_capabilities.requestMtu && mtu <= _defaultMtu) {
      throw const UnexpectedResult('The MTU stayed at 23');
    }
    return 'MTU $mtu';
  }, mtu: _mtu);

  /// Each piece replaces the echo, so it ends with the last piece.
  Future<String> _chunkedWrite() => _connected((connection) async {
    final echo = connection[ReferenceCharacteristic.echo];
    final value = ReferenceProfile.longValue;
    var pieces = 0;
    var previous = 0;
    var lastStart = 0;
    await echo.writeChunked(
      value,
      onProgress: (sent, _) {
        pieces++;
        lastStart = previous;
        previous = sent;
      },
      cancelToken: _cancel,
    );
    ValueMismatch.check(
      'the echo after the last piece',
      await echo.read(cancelToken: _cancel),
      value.sublist(lastStart),
    );
    metrics['chunkedPieces'] = pieces;
    return '${value.length} bytes in $pieces pieces';
  });

  Future<String> _includedService() => _connected((connection) async {
    final lab = connection.peripheral.services.firstWhere(
      (s) => s.uuid == ReferenceProfile.service,
    );
    final included =
        lab.includedServices
            .where((s) => s.uuid == ReferenceProfile.includedService)
            .firstOrNull ??
        (throw const UnexpectedResult(
          'The Lab service does not include the included service',
        ));
    ValueMismatch.check(
      'the included characteristic',
      await included.characteristics.single.read(cancelToken: _cancel),
      ReferenceProfile.includedValue,
    );
    return '${included.isPrimary ? 'primary' : 'secondary'} service found '
        'and read';
  });

  Future<String> _cacheRefresh() async {
    if (!_capabilities.gattCacheRefresh) return _notOffered;
    return _connected((connection) async {
      final peripheral = connection.peripheral;
      if (!await peripheral.clearGattCache(cancelToken: _cancel)) {
        return 'Android refused BluetoothGatt.refresh()';
      }
      final services = await peripheral.discoverServices(cancelToken: _cancel);
      if (!services.any((s) => s.uuid == ReferenceProfile.service)) {
        throw const UnexpectedResult(
          'Rediscovery after clearing the cache missed the Lab service',
        );
      }
      return 'cleared; rediscovered ${services.length} services';
    });
  }

  Future<String> _adapterName() async {
    if (!_capabilities.adapterName) return _notOffered;
    final name = await _bt.adapterName();
    return name == null ? 'no name' : '"$name"';
  }

  Future<String> _advertisingUpdate() async {
    if (!_capabilities.peripheralRole) return _notOffered;
    await _bt.requestPermissions(BtKit.peripheralPermissions);
    final session = await _bt.startAdvertising(_beacon(1));
    try {
      await session.update(_beacon(2), cancelToken: _cancel);
      return 'started and updated';
    } finally {
      await session.stop();
    }
  }

  /// Advertises no service UUID, so that no Lab scan finds it.
  AdvertiseOptions _beacon(int value) => _capabilities.advertiseCustomData
      ? AdvertiseOptions(
          manufacturerData: {
            ReferenceProfile.manufacturerId: Uint8List.fromList([value]),
          },
          connectable: false,
        )
      : AdvertiseOptions(localName: 'bt_kit Lab $value');

  Future<String> _periodicAdvertising() async {
    if (!_capabilities.periodicAdvertising) return _notOffered;
    await _bt.requestPermissions(BtKit.peripheralPermissions);
    const interval = Duration(milliseconds: 200);
    AdvertiseOptions periodic(int value) => AdvertiseOptions(
      extended: true,
      connectable: false,
      periodic: PeriodicAdvertising(
        interval: interval,
        manufacturerData: {
          ReferenceProfile.manufacturerId: Uint8List.fromList([value]),
        },
      ),
    );
    final session = await _bt.startAdvertising(periodic(1));
    try {
      await session.update(periodic(2), cancelToken: _cancel);
      return 'started and updated every ${interval.inMilliseconds} ms';
    } finally {
      await session.stop();
    }
  }

  Future<String> _connected(
    Future<String> Function(LabConnection connection) body, {
    int? mtu,
  }) async {
    final connection = await steps.context.connect(mtu: mtu);
    try {
      return await body(connection);
    } finally {
      await quietly(connection.close);
    }
  }
}
