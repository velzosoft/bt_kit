import 'package:meta/meta.dart';

import 'bluetooth_connection_state.dart';

/// A Bluetooth audio profile whose state Android reports.
enum AudioProfile {
  /// Advanced Audio Distribution: music and media.
  a2dp,

  /// Hands-Free and Headset: calls.
  headset,

  /// LE Audio.
  leAudio,

  /// Android's ASHA hearing aid profile.
  hearingAid,
}

/// The state of one audio profile on one remote device.
@immutable
final class AudioConnection {
  const AudioConnection({
    required this.deviceId,
    required this.profile,
    required this.state,
    this.deviceName,
    this.isPlaying = false,
  });

  /// The device's MAC address.
  final String deviceId;
  final String? deviceName;
  final AudioProfile profile;
  final BluetoothConnectionState state;

  /// Whether A2DP is streaming to the device; false for other profiles.
  final bool isPlaying;

  @override
  bool operator ==(Object other) =>
      other is AudioConnection &&
      other.deviceId == deviceId &&
      other.profile == profile &&
      other.state == state &&
      other.isPlaying == isPlaying;

  @override
  int get hashCode => Object.hash(deviceId, profile, state, isPlaying);

  @override
  String toString() =>
      'AudioConnection($deviceId, ${profile.name}, ${state.name}'
      '${isPlaying ? ', playing' : ''})';
}
