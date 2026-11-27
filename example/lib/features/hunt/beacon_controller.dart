import 'dart:async';
import 'dart:math';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../bluetooth/beacon_code.dart';
import '../../bluetooth/bluetooth_errors.dart';

enum BeaconStatus {
  starting,
  advertising,
  needsPermission,
  unsupported,
  failed,
}

/// Advertises this phone as a Hunt target, with a random code, for as long
/// as the controller lives.
final class BeaconController extends ChangeNotifier {
  BeaconController({BtKit? bt, Random? random})
    : _bt = bt ?? BtKit.instance,
      code = BeaconCode.generate(random);

  final String code;
  final BtKit _bt;
  AdvertisingSession? _advertising;
  var _status = BeaconStatus.starting;
  String? _message;
  var _disposed = false;

  BeaconStatus get status => _status;

  /// Why the beacon is not advertising.
  String? get message => _message;

  Future<void> start() async {
    if (_advertising != null) return;
    _set(BeaconStatus.starting);
    final capabilities = _bt.capabilities;
    if (!capabilities.peripheralRole) {
      return _set(
        BeaconStatus.unsupported,
        'This phone cannot advertise over Bluetooth, so other phones '
        'cannot hunt for it.',
      );
    }
    try {
      final statuses = await _bt.requestPermissions(
        BtKit.peripheralPermissions,
      );
      if (describeMissingPermissions(statuses) case final missing?) {
        return _set(BeaconStatus.needsPermission, missing);
      }
      final advertising = await _bt.startAdvertising(
        BeaconCode.advertiseOptions(code, capabilities),
      );
      if (_disposed) return await advertising.stop();
      _advertising = advertising;
      _set(BeaconStatus.advertising);
    } on BluetoothException catch (e) {
      _set(BeaconStatus.failed, describeBluetoothError(e));
    }
  }

  void _set(BeaconStatus status, [String? message]) {
    if (_disposed) return;
    _status = status;
    _message = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_advertising?.stop().catchError((Object _) {}));
    super.dispose();
  }
}
