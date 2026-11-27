import 'dart:async';
import 'dart:ffi';

import 'package:objective_c/objective_c.dart' as objc;

import '../../central/native_types.dart';
import '../../core/exceptions.dart';
import '../../core/native_handle.dart';
import '../../models/companion_request.dart';
import '../../native/ios/bindings.dart';
import '../companion_backend.dart';
import 'objc_conversions.dart';

/// Companion accessories through AccessorySetupKit's `ASAccessorySession`.
///
/// Platform quirks handled here:
/// * The session reports everything through one event handler on a
///   dispatch queue, and must be activated before anything else.
/// * The picker's completion only says whether it was shown; the chosen
///   accessory arrives as an `accessoryAdded` event, and the picker's end as
///   `pickerDidDismiss`.
/// * Each picker item needs a product image; a system symbol stands in when
///   the app gives none.
final class IosCompanion implements CompanionBackend {
  static const _placeholderSymbol = 'dot.radiowaves.left.and.right';

  ASAccessorySession? _session;
  Completer<void>? _activated;
  _Picking? _picking;
  final _changes = StreamController<CompanionChange>.broadcast();

  @override
  Future<CompanionDeviceBackend?> associate(CompanionRequest request) async {
    if (request.service == null && request.manufacturerId == null) {
      throw ArgumentError(
        'AccessorySetupKit needs a service or a manufacturerId to look for',
      );
    }
    final session = await _active();
    if (_picking != null) {
      throw const NativeOperationException('The picker is already showing');
    }
    final picking = _picking = _Picking();
    final item = ASPickerDisplayItem.alloc().initWithName(
      request.displayName.toNSString(),
      productImage: _image(request),
      descriptor: _descriptor(request),
    );
    session.showPickerForDisplayItems(
      objc.NSArray.of([item]),
      completionHandler: ObjCBlock_ffiVoid_NSError.listener((error) {
        if (error == null) return;
        if (error.code == ASErrorCode.ASErrorCodeUserCancelled.value) {
          picking.finish();
        } else {
          picking.fail(errorOf(error, 'showPicker'));
        }
      }),
    );
    try {
      final accessory = await picking.result;
      return accessory == null ? null : IosCompanionDevice(accessory);
    } finally {
      _picking = null;
    }
  }

  @override
  Future<List<CompanionDeviceBackend>> devices() async => listOf(
    (await _active()).accessories,
    (o) => IosCompanionDevice(ASAccessory.as(o)),
  );

  @override
  Future<void> remove(CompanionDeviceBackend device) async {
    final session = await _active();
    final removed = Completer<void>();
    session.removeAccessory(
      device.native.ios!,
      completionHandler: ObjCBlock_ffiVoid_NSError.listener((error) {
        if (error == null) {
          removed.complete();
        } else {
          removed.completeError(errorOf(error, 'removeAccessory'));
        }
      }),
    );
    return removed.future;
  }

  @override
  Stream<CompanionChange> get changes => _changes.stream;

  @override
  Future<void> observePresence(
    CompanionDeviceBackend device, {
    required bool observe,
  }) => throw const UnsupportedFeatureException(
    'companionPresence',
    'iOS reports accessories through state restoration instead',
  );

  Future<ASAccessorySession> _active() async {
    final session = _session ??= ASAccessorySession.alloc().init()
      ..activateWithQueue(
        _mainQueue,
        eventHandler: ObjCBlock_ffiVoid_ASAccessoryEvent.listener(_onEvent),
      );
    await (_activated ??= Completer()).future;
    return session;
  }

  void _onEvent(ASAccessoryEvent event) {
    final accessory = event.accessory;
    switch (event.eventType) {
      case ASAccessoryEventType.ASAccessoryEventTypeActivated:
        _activated?.complete();
      case ASAccessoryEventType.ASAccessoryEventTypeInvalidated:
        final activating = _activated;
        _session = null;
        _activated = null;
        final ended = NativeOperationException(
          'AccessorySetupKit ended the session'
          '${event.error == null ? '' : ': ${event.error!.localizedDescription.toDartString()}'}',
          nativeError: event.error,
        );
        if (activating != null && !activating.isCompleted) {
          activating.completeError(ended);
        }
        _picking?.fail(ended);
      case ASAccessoryEventType.ASAccessoryEventTypeAccessoryAdded
          when accessory != null:
        final picking = _picking;
        if (picking != null) {
          picking.added = accessory;
        } else {
          _report(accessory, CompanionChangeKind.added);
        }
      case ASAccessoryEventType.ASAccessoryEventTypeAccessoryRemoved
          when accessory != null:
        _report(accessory, CompanionChangeKind.removed);
      case ASAccessoryEventType.ASAccessoryEventTypeAccessoryChanged
          when accessory != null:
        _report(accessory, CompanionChangeKind.changed);
      case ASAccessoryEventType.ASAccessoryEventTypePickerDidDismiss:
        _picking?.finish();
      default:
    }
  }

  void _report(ASAccessory accessory, CompanionChangeKind kind) =>
      _changes.add((device: IosCompanionDevice(accessory), kind: kind));

  static ASDiscoveryDescriptor _descriptor(CompanionRequest request) {
    final descriptor = ASDiscoveryDescriptor.alloc().init();
    if (request.service case final uuid?) {
      descriptor.bluetoothServiceUUID = cbUuid(uuid);
    }
    if (request.nameContains case final name?) {
      descriptor.bluetoothNameSubstring = name.toNSString();
    }
    if (request.manufacturerId case final company?) {
      descriptor.bluetoothCompanyIdentifier = company;
    }
    if (request.manufacturerData case final data?) {
      descriptor
        ..bluetoothManufacturerDataBlob = data.toNSData()
        ..bluetoothManufacturerDataMask = [
          for (var i = 0; i < data.length; i++)
            i < (request.manufacturerDataMask?.length ?? 0)
                ? request.manufacturerDataMask![i]
                : 0xff,
        ].toNSData();
    }
    return descriptor;
  }

  static UIImage _image(CompanionRequest request) {
    final bytes = request.productImage;
    final image = bytes == null
        ? null
        : UIImage.imageWithData(bytes.toNSData());
    return image ??
        UIImage.systemImageNamed(_placeholderSymbol.toNSString()) ??
        UIImage.alloc().init();
  }

  /// `dispatch_get_main_queue()` is a macro for this symbol's address.
  static final objc.NSObject _mainQueue = objc.NSObject.fromPointer(
    DynamicLibrary.process().lookup<Void>('_dispatch_main_q').cast(),
    retain: true,
    release: true,
  );
}

/// A picker on screen, collecting the accessory the user adds.
final class _Picking {
  final _result = Completer<ASAccessory?>();
  ASAccessory? added;

  Future<ASAccessory?> get result => _result.future;

  void finish() {
    if (!_result.isCompleted) _result.complete(added);
  }

  void fail(BluetoothException error) {
    if (!_result.isCompleted) _result.completeError(error);
  }
}

/// One `ASAccessory`.
final class IosCompanionDevice implements CompanionDeviceBackend {
  IosCompanionDevice(this._accessory)
    : peripheralId = _accessory.bluetoothIdentifier?.UUIDString.toDartString(),
      name = _accessory.displayName.toDartString();

  final ASAccessory _accessory;

  @override
  final String? peripheralId;

  @override
  final String? name;

  @override
  String get id => peripheralId ?? '${keyOf(_accessory)}';

  @override
  CompanionHandle get native => IosHandle(_accessory);
}
