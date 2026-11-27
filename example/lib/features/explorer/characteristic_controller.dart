import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import 'attribute_controller.dart';
import 'failure_text.dart';
import 'value_log.dart';

/// Reads, writes and subscriptions for one characteristic.
final class CharacteristicController extends AttributeController {
  CharacteristicController(this.characteristic)
    : descriptors = [
        for (final descriptor in characteristic.descriptors)
          DescriptorController(descriptor),
      ];

  final GattCharacteristic characteristic;
  final List<DescriptorController> descriptors;
  final log = ValueLog();
  StreamSubscription<Uint8List>? _subscription;

  CharacteristicProperties get properties => characteristic.properties;

  bool get canWrite => properties.write || properties.writeWithoutResponse;

  bool get canSubscribe => properties.notify || properties.indicate;

  bool get isSubscribed => _subscription != null;

  Future<void> read() => perform(() async {
    receive(TimedValue(await characteristic.read()));
    return null;
  });

  /// A write without response only reaches the platform's queue, so its
  /// status says "sent", not "wrote".
  Future<void> write(List<int> value, {required bool withResponse}) =>
      perform(() async {
        await characteristic.write(value, withResponse: withResponse);
        final size = value.length == 1 ? '1 byte' : '${value.length} bytes';
        return withResponse ? 'Wrote $size' : 'Sent $size without response';
      });

  void setSubscribed(bool subscribed) {
    if (subscribed == isSubscribed) return;
    if (!subscribed) return _stop();
    _subscription = characteristic.subscribe().listen(
      _onValue,
      onError: _onError,
      onDone: _stop,
    );
    report(null);
  }

  void clearLog() {
    log.clear();
    changed();
  }

  void _onValue(Uint8List bytes) {
    final value = TimedValue(bytes);
    log.add(value);
    receive(value);
  }

  void _onError(Object error) {
    _stop();
    report(
      error is BluetoothException ? explainFailure(error) : '$error',
      failed: true,
    );
  }

  void _stop() {
    final subscription = _subscription;
    _subscription = null;
    unawaited(subscription?.cancel());
    changed();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    for (final descriptor in descriptors) {
      descriptor.dispose();
    }
    super.dispose();
  }
}
