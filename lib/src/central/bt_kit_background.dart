part of 'bt_kit.dart';

/// The entry point of the headless engine Android starts for background
/// events while no engine listens to them.
@pragma('vm:entry-point')
Future<void> _backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bt = BtKit.instance;
  final background = bt._backend.background..acknowledgeEvents();
  final raw = background.handlerHandle;
  final handler = raw == null
      ? null
      : PluginUtilities.getCallbackFromHandle(CallbackHandle.fromRawHandle(raw))
            as BackgroundHandler?;
  if (handler == null) {
    BtLog.background.warning(
      () => 'No background handler is registered; dropping events',
    );
  }
  await for (final event in bt.backgroundEvents) {
    try {
      await handler?.call(event);
    } on Object catch (error) {
      BtLog.background.warning(
        () => 'The background handler failed on $event',
        error,
      );
    } finally {
      background.handled();
    }
  }
}

extension on BtKit {
  Iterable<BackgroundEvent> _backgroundEvents(BackgroundSignal signal) sync* {
    switch (signal) {
      case ScanSignal(:final hits, :final errorCode):
        BtLog.background.info(
          () =>
              'Background scan: ${hits.length} results'
              '${errorCode == null ? '' : ', error $errorCode'}',
        );
        yield BackgroundScanResult([
          for (final hit in hits) _advertisement(hit),
        ], errorCode: errorCode);
      case PresenceSignal(:final associationId, :final presence):
        BtLog.background.info(
          () => 'Companion $associationId: ${presence.name}',
        );
        yield CompanionPresenceChanged('$associationId', presence);
    }
  }
}
