import '../central/advertisement.dart';

/// A Bluetooth event the system delivered to the app, possibly while it
/// was not running (Android).
///
/// Events reach `BtKit.backgroundEvents` while an engine listens to it.
/// Otherwise the system starts the app in the background and a headless
/// engine runs the handler registered with `BtKit.registerBackgroundHandler`.
sealed class BackgroundEvent {
  const BackgroundEvent();
}

/// Results of the scan started with `BtKit.startBackgroundScan`.
final class BackgroundScanResult extends BackgroundEvent {
  const BackgroundScanResult(this.advertisements, {this.errorCode});

  final List<Advertisement> advertisements;

  /// Set when the scan failed and the system stopped it: a
  /// `ScanCallback.SCAN_FAILED_*` code.
  final int? errorCode;

  @override
  String toString() =>
      'BackgroundScanResult(${advertisements.length} advertisements'
      '${errorCode == null ? '' : ', error $errorCode'})';
}

/// A companion device observed with
/// `CompanionDevices.startObservingPresence` came or went.
final class CompanionPresenceChanged extends BackgroundEvent {
  const CompanionPresenceChanged(this.companionId, this.presence);

  /// The `CompanionDevice.id`.
  final String companionId;
  final CompanionPresence presence;

  @override
  String toString() =>
      'CompanionPresenceChanged($companionId, ${presence.name})';
}

enum CompanionPresence {
  /// The device came into range (LE).
  appeared,

  /// The device left range (LE).
  disappeared,

  /// The device connected over Bluetooth Classic (Android 16 and later).
  connected,

  /// The device disconnected over Bluetooth Classic (Android 16 and later).
  disconnected,

  /// The association was removed, by the user or the system.
  removed,
}

/// Handles background events in a headless engine; register it with
/// `BtKit.registerBackgroundHandler`. It must be a top-level or static
/// function annotated with `@pragma('vm:entry-point')`.
typedef BackgroundHandler = Future<void> Function(BackgroundEvent event);
