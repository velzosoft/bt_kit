import 'dart:convert';
import 'dart:math';

import 'package:bt_kit/bt_kit.dart';

import 'app_uuids.dart';

/// The short code a phone in beacon mode advertises, so that hunters can
/// tell beacons apart.
abstract final class BeaconCode {
  static const length = 4;

  /// No 0, O, 1 or I, which are easy to mix up when read aloud.
  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static const _namePrefix = 'Radar ';
  static final _pattern = RegExp('^[$alphabet]{$length}\$');

  static String generate([Random? random]) {
    final source = random ?? Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < length; i++)
        alphabet.codeUnitAt(source.nextInt(alphabet.length)),
    ]);
  }

  static bool isValid(String code) => _pattern.hasMatch(code);

  static String localName(String code) => '$_namePrefix$code';

  /// iOS advertises only a local name and service UUIDs, so the code goes
  /// into the name. Android cannot set a name but can send service data.
  /// A legacy advertisement holds 31 bytes: room for the 128-bit service
  /// data or the 128-bit service UUID, not both, so Android sends only the
  /// service data.
  static AdvertiseOptions advertiseOptions(
    String code,
    BluetoothCapabilities capabilities,
  ) {
    final customData = capabilities.advertiseCustomData;
    return AdvertiseOptions(
      localName: capabilities.advertiseLocalName ? localName(code) : null,
      serviceUuids: customData ? const [] : [AppUuids.beacon],
      serviceData: customData
          ? {AppUuids.beacon: ascii.encode(code)}
          : const {},
      mode: AdvertiseMode.lowLatency,
      txPower: AdvertiseTxPower.high,
    );
  }

  /// The code in an advertisement from a phone in beacon mode, if any.
  static String? read(AdvertisementData data) {
    final payload = data.serviceData[AppUuids.beacon];
    if (payload != null) return _valid(String.fromCharCodes(payload));
    final name = data.localName;
    if (name == null ||
        !name.startsWith(_namePrefix) ||
        !data.serviceUuids.contains(AppUuids.beacon)) {
      return null;
    }
    return _valid(name.substring(_namePrefix.length));
  }

  static String? _valid(String code) => isValid(code) ? code : null;
}
