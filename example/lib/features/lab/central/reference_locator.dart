import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../../../bluetooth/scanner.dart';
import '../profile/reference_profile.dart';

/// Finds reference peripherals by the Lab service UUID they advertise.
abstract final class ReferenceLocator {
  static bool advertises(AdvertisementData data) =>
      data.serviceUuids.contains(ReferenceProfile.service);

  /// The first reference peripheral heard within [timeout], or null.
  ///
  /// It listens with the app's shared scan options, so it joins a scan that
  /// is already running instead of conflicting with it.
  static Future<Peripheral?> find({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final found = Completer<Peripheral?>();
    void finish(Peripheral? peripheral) {
      if (!found.isCompleted) found.complete(peripheral);
    }

    final subscription = BtKit.instance
        .scan(Scanner.options)
        .listen(
          (ad) {
            if (advertises(ad.data)) finish(ad.peripheral);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!found.isCompleted) found.completeError(error, stackTrace);
          },
          onDone: () => finish(null),
        );
    final timer = Timer(timeout, () => finish(null));
    try {
      return await found.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }
  }
}
