import 'package:bt_kit/bt_kit.dart';

import '../profile/fault_command.dart';
import '../profile/reference_profile.dart';
import '../profile/stream_command.dart';
import 'reference_characteristics.dart';

/// A connection to the reference peripheral with its profile discovered.
final class LabConnection {
  LabConnection._(this.peripheral, this._characteristics);

  static Future<LabConnection> open(
    Peripheral peripheral, {
    required Duration timeout,
    int? mtu,
    CancelToken? cancelToken,
  }) async {
    await peripheral.connect(
      mtu: mtu,
      timeout: timeout,
      cancelToken: cancelToken,
    );
    try {
      await peripheral.discoverServices(cancelToken: cancelToken);
      return LabConnection._(
        peripheral,
        ReferenceCharacteristics.of(peripheral),
      );
    } on Object {
      await peripheral.disconnect();
      rethrow;
    }
  }

  final Peripheral peripheral;
  final ReferenceCharacteristics _characteristics;

  GattCharacteristic operator [](ReferenceCharacteristic characteristic) =>
      _characteristics[characteristic];

  GattCharacteristic stream(StreamKind kind) =>
      this[switch (kind) {
        StreamKind.notify => ReferenceCharacteristic.notifyStream,
        StreamKind.indicate => ReferenceCharacteristic.indicateStream,
      }];

  Future<void> startStream(
    StreamKind kind,
    int rateHz, {
    CancelToken? cancelToken,
  }) => this[ReferenceCharacteristic.streamControl].write(
    StartStream(kind, rateHz).encode(),
    cancelToken: cancelToken,
  );

  Future<void> stopStream() => this[ReferenceCharacteristic.streamControl]
      .write(const StopStream().encode());

  Future<void> setFault(GattError? fault) =>
      this[ReferenceCharacteristic.faultControl].write(
        FaultCommand.encode(fault),
      );

  Future<String> readInfo() async => ReferenceProfile.describeInfo(
    await this[ReferenceCharacteristic.info].read(),
  );

  /// Asks Android for a short connection interval; false where the
  /// platform chooses it or refuses.
  Future<bool> requestHighPriority() async {
    if (!BtKit.instance.capabilities.connectionPriority) return false;
    try {
      await peripheral.requestConnectionPriority(ConnectionPriority.high);
      return true;
    } on NativeOperationException {
      return false;
    }
  }

  Future<void> close() => peripheral.disconnect();
}
