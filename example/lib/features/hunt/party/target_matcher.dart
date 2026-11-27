import 'package:bt_kit/bt_kit.dart';

import '../../../bluetooth/beacon_code.dart';
import 'target_fingerprint.dart';

/// Ordered from least to most sure.
enum MatchConfidence { none, weak, strong, certain }

/// Scores how likely a device a seeker's phone hears is the hider's target.
abstract final class TargetMatcher {
  /// * A beacon code or, between Android phones, the address: certain.
  /// * The advertised name, from the same manufacturer: strong.
  /// * The manufacturer and services alone: weak, since similar devices
  ///   share them.
  static MatchConfidence confidence(
    TargetFingerprint target, {
    required String id,
    required AdvertisementData data,
    required bool idsAreAddresses,
  }) {
    if (target.beaconCode case final code?) {
      return BeaconCode.read(data) == code
          ? MatchConfidence.certain
          : MatchConfidence.none;
    }
    if (target.address case final address?
        when idsAreAddresses && id.toUpperCase() == address.toUpperCase()) {
      return MatchConfidence.certain;
    }
    final sameCompany =
        target.company == null ||
        data.manufacturerData.containsKey(target.company);
    if (target.localName case final name?) {
      if (data.localName == name) {
        return sameCompany ? MatchConfidence.strong : MatchConfidence.weak;
      }
      if (data.localName != null) return MatchConfidence.none;
    }
    final advertised = {...data.serviceUuids, ...data.serviceData.keys};
    final hasTraits = target.company != null || target.services.isNotEmpty;
    return hasTraits && sameCompany && advertised.containsAll(target.services)
        ? MatchConfidence.weak
        : MatchConfidence.none;
  }
}

/// A device that may be the target.
final class TargetMatch<T> {
  const TargetMatch(this.device, this.confidence, this.rssi);

  final T device;
  final MatchConfidence confidence;
  final double rssi;

  /// The likely matches, best first: by confidence, then by signal.
  static List<TargetMatch<T>> rank<T>(Iterable<TargetMatch<T>> matches) =>
      [
        for (final match in matches)
          if (match.confidence != MatchConfidence.none) match,
      ]..sort((a, b) {
        final byConfidence = b.confidence.index.compareTo(a.confidence.index);
        return byConfidence != 0 ? byConfidence : b.rssi.compareTo(a.rssi);
      });

  /// Whether the best two of [ranked] are equally likely, so that the
  /// seeker should choose.
  static bool isAmbiguous(List<TargetMatch<Object?>> ranked) =>
      ranked.length > 1 && ranked[0].confidence == ranked[1].confidence;
}
