import '../core/exceptions.dart';
import '../models/audio_connection.dart';
import '../models/capabilities.dart';
import '../models/permission.dart';
import '../platform/audio_backend.dart';

/// The state of the system's Bluetooth audio links (Android): which
/// devices are connected for media, calls, LE Audio or hearing aids.
/// Read-only; the system owns audio routing. Reach it through `BtKit.audio`.
final class AudioProfiles {
  AudioProfiles._(this._backend, this._capabilities, this._ensureReady);

  final AudioBackend _backend;
  final BluetoothCapabilities Function() _capabilities;
  final Future<void> Function(Set<BluetoothPermission>) _ensureReady;

  /// The devices connected through [profiles].
  Future<List<AudioConnection>> connections([
    Set<AudioProfile> profiles = const {...AudioProfile.values},
  ]) async {
    _require();
    await _ensureReady(const {BluetoothPermission.connect});
    return _backend.connections(profiles);
  }

  /// Connection and playing state changes on every audio profile.
  Stream<AudioConnection> get changes async* {
    _require();
    await _ensureReady(const {BluetoothPermission.connect});
    yield* _backend.changes;
  }

  void _require() {
    if (!_capabilities().audioProfiles) {
      throw const UnsupportedFeatureException(
        'audioProfiles',
        'iOS keeps audio links to itself; AVAudioSession reports the '
            'current route',
      );
    }
  }
}

AudioProfiles createAudioProfiles(
  AudioBackend backend,
  BluetoothCapabilities Function() capabilities,
  Future<void> Function(Set<BluetoothPermission>) ensureReady,
) => AudioProfiles._(backend, capabilities, ensureReady);
