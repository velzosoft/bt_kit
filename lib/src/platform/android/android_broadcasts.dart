import 'dart:async';

import 'package:jni/jni.dart';

import '../../core/log.dart';
import '../../native/android/bindings.dart';
import 'jni_conversions.dart';

/// Bluetooth broadcasts for [actions], parsed by [parse], as a broadcast
/// stream. The receiver is registered while the stream has listeners, and
/// each intent is released once parsed.
///
/// The Bluetooth process sends these broadcasts, not the system server, and
/// a receiver registered with `RECEIVER_NOT_EXPORTED` only hears the system
/// server and its own app. The receiver is therefore exported; every action
/// it takes is a protected broadcast, which no other app can send.
Stream<T> androidBroadcasts<T extends Object>(
  Context context,
  List<JString?> actions,
  T? Function(Intent intent) parse,
) {
  BroadcastReceiver? receiver;
  late final StreamController<T> controller;
  controller = StreamController<T>.broadcast(
    onListen: () {
      final registered = receiver = BroadcastReceiver.implement(
        onReceive: (_, intent) {
          if (intent == null) return;
          try {
            final value = parse(intent);
            if (value != null) controller.add(value);
          } on Object catch (error) {
            BtLog.adapter.warning(() => 'Dropped a broadcast', error);
          } finally {
            intent.release();
          }
        },
      );
      final filter = IntentFilter();
      for (final action in actions) {
        filter.addAction(action);
      }
      guardJni(
        'Registering a broadcast receiver',
        () => context.registerReceiver$1(
          registered,
          filter,
          Context.RECEIVER_EXPORTED,
        ),
      );
      filter.release();
    },
    onCancel: () {
      final registered = receiver;
      receiver = null;
      if (registered == null) return;
      guardJni(
        'Unregistering a broadcast receiver',
        () => context.unregisterReceiver(registered),
      );
      registered.release();
    },
  );
  return controller.stream;
}

final _deviceClass = BluetoothDevice.type.jClass;

/// The `BluetoothDevice` a Bluetooth broadcast is about.
BluetoothDevice? deviceExtra(Intent intent) =>
    intent.getParcelableExtra<BluetoothDevice?>(
      BluetoothDevice.EXTRA_DEVICE,
      _deviceClass,
    );

/// The MAC address of the device a Bluetooth broadcast is about.
String? addressExtra(Intent intent) {
  final device = deviceExtra(intent);
  final address = takeString(device?.address);
  device?.release();
  return address;
}
