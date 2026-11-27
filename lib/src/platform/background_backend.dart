import '../background/background_event.dart';
import '../models/scan_options.dart';
import 'central_backend.dart';

/// Events the system delivers while the app may not be running (Android).
abstract interface class BackgroundBackend {
  /// Starts a scan that keeps running while the app is not, replacing the
  /// previous one.
  Future<void> startScan(ScanOptions options);

  Future<void> stopScan();

  /// Events for this engine. While it listens, the platform sends them here
  /// instead of to a headless engine.
  Stream<BackgroundSignal> get signals;

  /// Stores the callbacks a headless engine runs.
  void register(int dispatcherHandle, int handlerHandle);

  int? get handlerHandle;

  /// Makes this engine acknowledge each event with [handled], so that the
  /// platform keeps the process alive until it has. The headless engine
  /// does this before it listens to [signals].
  void acknowledgeEvents();

  /// The oldest event not yet acknowledged has been handled.
  void handled();
}

sealed class BackgroundSignal {
  const BackgroundSignal();
}

final class ScanSignal extends BackgroundSignal {
  const ScanSignal(this.hits, {this.errorCode});

  final List<ScanHit> hits;

  /// Set when the scan failed; the system stopped it.
  final int? errorCode;
}

final class PresenceSignal extends BackgroundSignal {
  const PresenceSignal(this.associationId, this.presence);

  final int associationId;
  final CompanionPresence presence;
}
