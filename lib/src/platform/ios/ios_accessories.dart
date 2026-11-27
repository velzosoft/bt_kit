import 'dart:async';

import 'package:objective_c/objective_c.dart' as objc;

import '../../core/exceptions.dart';
import '../../native/ios/bindings.dart';
import '../accessory_backend.dart';
import '../channel_backend.dart';
import 'ios_streams.dart';
import 'objc_conversions.dart';

/// MFi accessories through `EAAccessoryManager` and `EASession`.
///
/// Platform quirks handled here:
/// * Connections are reported only as `NSNotification`s, and only after
///   `registerForLocalNotifications`.
/// * The picker reports through its completion block whether the user
///   chose an accessory; the accessory itself connects later.
/// * `EASession` returns nil when the protocol is not listed under
///   `UISupportedExternalAccessoryProtocols` or already has a session.
final class IosAccessories implements AccessoryBackend {
  late final _manager = EAAccessoryManager.sharedAccessoryManager();
  final _observers = <objc.NSObjectProtocol>[];
  late final _changes =
      StreamController<
        ({AccessoryBackendItem accessory, bool connected})
      >.broadcast(onListen: _observe, onCancel: _stopObserving);

  @override
  List<AccessoryBackendItem> get connected => listOf(
    _manager.connectedAccessories,
    (o) => IosAccessory(EAAccessory.as(o)),
  );

  @override
  Stream<({AccessoryBackendItem accessory, bool connected})> get changes =>
      _changes.stream;

  @override
  Future<void> showBluetoothPicker() {
    final dismissed = Completer<void>();
    _manager.showBluetoothAccessoryPickerWithNameFilter(
      null,
      completion: ObjCBlock_ffiVoid_NSError.listener((error) {
        final code = error?.code;
        if (error == null ||
            code ==
                EABluetoothAccessoryPickerErrorCode
                    .EABluetoothAccessoryPickerResultCancelled
                    .value ||
            code ==
                EABluetoothAccessoryPickerErrorCode
                    .EABluetoothAccessoryPickerAlreadyConnected
                    .value) {
          dismissed.complete();
        } else {
          dismissed.completeError(
            NativeOperationException(
              'The accessory picker failed: '
              '${error.localizedDescription.toDartString()}',
              nativeCode: code,
              nativeError: error,
            ),
          );
        }
      }),
    );
    return dismissed.future;
  }

  void _observe() {
    final center = NSNotificationCenter.getDefaultCenter();
    for (final (name, connected) in [
      (EAAccessoryDidConnectNotification, true),
      (EAAccessoryDidDisconnectNotification, false),
    ]) {
      _observers.add(
        center.addObserverForName(
          name,
          usingBlock: ObjCBlock_ffiVoid_NSNotification.listener((note) {
            final accessory = note.userInfo?.objectForKey(EAAccessoryKey);
            if (accessory == null) return;
            _changes.add((
              accessory: IosAccessory(EAAccessory.as(accessory)),
              connected: connected,
            ));
          }),
        ),
      );
    }
    _manager.registerForLocalNotifications();
  }

  void _stopObserving() {
    _manager.unregisterForLocalNotifications();
    final center = NSNotificationCenter.getDefaultCenter();
    for (final observer in _observers) {
      center.removeObserver(observer);
    }
    _observers.clear();
  }
}

/// One `EAAccessory`.
final class IosAccessory implements AccessoryBackendItem {
  IosAccessory(this.native);

  @override
  final EAAccessory native;

  @override
  int get connectionId => native.connectionID;

  @override
  String get name => native.name.toDartString();

  @override
  String get manufacturer => native.manufacturer.toDartString();

  @override
  String get modelNumber => native.modelNumber.toDartString();

  @override
  String get serialNumber => native.serialNumber.toDartString();

  @override
  String get firmwareRevision => native.firmwareRevision.toDartString();

  @override
  String get hardwareRevision => native.hardwareRevision.toDartString();

  @override
  List<String> get protocols =>
      listOf(native.protocolStrings, (o) => objc.NSString.as(o).toDartString());

  @override
  bool get isConnected => native.isConnected;

  @override
  Future<ByteChannelBackend<EASession>> openSession(String protocol) async {
    final session = EASession.alloc().initWithAccessory(
      native,
      forProtocol: protocol.toNSString(),
    );
    final input = session?.inputStream;
    final output = session?.outputStream;
    if (session == null || input == null || output == null) {
      throw NativeOperationException(
        'iOS did not open a session for $protocol: list it under '
        'UISupportedExternalAccessoryProtocols in Info.plist, and close any '
        'other session for it',
      );
    }
    return IosStreamChannel(session, '$connectionId', input, output);
  }
}
