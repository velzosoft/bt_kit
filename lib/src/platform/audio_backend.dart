import '../models/audio_connection.dart';

/// The state of Bluetooth audio profiles (Android).
abstract interface class AudioBackend {
  /// The devices connected through [profiles].
  Future<List<AudioConnection>> connections(Set<AudioProfile> profiles);

  /// Connection and playing state changes; reported while listened.
  Stream<AudioConnection> get changes;
}
