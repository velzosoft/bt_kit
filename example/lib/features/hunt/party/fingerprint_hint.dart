import 'target_fingerprint.dart';

const unnamedDevicesNote =
    'Unnamed devices only match reliably between Android phones.';

/// Tells the hider how seekers' phones will recognize [target].
String fingerprintHint(TargetFingerprint target) => switch (target) {
  TargetFingerprint(:final beaconCode?) =>
    'It is a BT Radar beacon with code $beaconCode, so every seeker’s phone '
        'will recognize it.',
  TargetFingerprint(address: _?, :final localName?) =>
    'Seekers’ phones will recognize it by its name, “$localName”, and '
        'Android phones by its address too.',
  TargetFingerprint(address: _?) =>
    'It has no name: Android phones will recognize it by its address, '
        'iPhones can only guess. $unnamedDevicesNote',
  TargetFingerprint(:final localName?) =>
    'Seekers’ phones will recognize it by its name, “$localName”.',
  _ when target.quality == FingerprintQuality.traits =>
    'It has no name, so seekers’ phones can only guess from its maker and '
        'services, and may ask them to pick it. $unnamedDevicesNote',
  _ =>
    'It advertises nothing that sets it apart, so seekers will have to pick '
        'it themselves. $unnamedDevicesNote',
};
