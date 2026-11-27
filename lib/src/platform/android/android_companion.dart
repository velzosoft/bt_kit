import 'dart:async';

import 'package:jni/jni.dart';

import '../../central/native_types.dart';
import '../../core/exceptions.dart';
import '../../core/native_handle.dart';
import '../../models/advertisement_filter.dart';
import '../../models/companion_request.dart';
import '../../native/android/bindings.dart';
import '../../native/android/bindings.g.dart' as raw show Pattern;
import '../companion_backend.dart';
import 'android_activity.dart';
import 'android_central.dart';
import 'jni_conversions.dart';

/// Companion device associations through `CompanionDeviceManager`.
///
/// Associating shows a system chooser: Android reports it through
/// `onAssociationPending`, the app starts it as an activity, and the
/// association arrives through `onAssociationCreated`.
final class AndroidCompanion implements CompanionBackend {
  AndroidCompanion(this._context, this._activity);

  /// `CompanionDeviceManager.removeBond` arrived in API 36 behind a feature
  /// flag, so its presence is checked rather than assumed.
  static final bool canRemoveBonds = () {
    if (Build$VERSION.SDK_INT < 36) return false;
    try {
      JClass.forName('android/companion/CompanionDeviceManager')
          .instanceMethodId('removeBond', '(I)Z');
      return true;
    } on Object {
      return false;
    }
  }();

  static const _presenceRequestApi = 36;

  /// The reasons `onFailure(CharSequence)` gives when the user dismissed
  /// the chooser. With a `Handler`, every API level reports a dismissal only
  /// this way; the coded `onFailure` needs an `Executor`.
  static const _dismissals = {'user_rejected', 'canceled'};

  final Context _context;
  final AndroidActivity _activity;
  final _pending = <CompanionDeviceManager$Callback>{};
  late final CompanionDeviceManager? _manager = _context
      .getSystemService$1(Context.COMPANION_DEVICE_SERVICE!)
      ?.as(CompanionDeviceManager.type, releaseOriginal: true);

  CompanionDeviceManager get manager =>
      _manager ??
      (throw const UnsupportedFeatureException(
        'companionDevices',
        'This device has no CompanionDeviceManager',
      ));

  @override
  Future<CompanionDeviceBackend?> associate(CompanionRequest request) async {
    final info = await _associate(_request(request));
    return info == null ? null : AndroidAssociation(info);
  }

  @override
  Future<List<CompanionDeviceBackend>> devices() async => [
    for (final info in _associations()) AndroidAssociation(info),
  ];

  @override
  Future<void> remove(CompanionDeviceBackend device) async {
    final id = int.parse(device.id);
    guardJni('Removing an association', () => manager.disassociate(id));
  }

  @override
  Stream<CompanionChange> get changes => const Stream.empty();

  @override
  Future<void> observePresence(
    CompanionDeviceBackend device, {
    required bool observe,
  }) async {
    final manager = this.manager;
    if (Build$VERSION.SDK_INT >= _presenceRequestApi) {
      final request =
          (ObservingDevicePresenceRequest$Builder()
                ..setAssociationId(int.parse(device.id)))
              .build();
      guardJni(
        'Observing presence',
        () => observe
            ? manager.startObservingDevicePresence(request)
            : manager.stopObservingDevicePresence(request),
      );
      request.release();
      return;
    }
    final address = device.peripheralId;
    if (address == null) {
      throw ArgumentError.value(device.id, 'device', 'Has no MAC address');
    }
    guardJni(
      'Observing presence',
      () => observe
          ? manager.startObservingDevicePresence$1(address.toJString())
          : manager.stopObservingDevicePresence$1(address.toJString()),
    );
  }

  /// The association for the device with [address], created with the
  /// user's confirmation if there is none yet.
  Future<int> associationFor(String address) async {
    for (final info in _associations()) {
      if (_address(info) == address) return info.id;
    }
    final filter =
        (BluetoothDeviceFilter$Builder()..setAddress(address.toJString()))
            .build();
    final request =
        (AssociationRequest$Builder()
              ..addDeviceFilter(filter)
              ..setSingleDevice(true))
            .build();
    final info = await _associate(request);
    if (info == null) {
      throw const BondException(
        'Removing a bond needs a companion association, which the user '
        'did not confirm',
      );
    }
    return info.id;
  }

  bool removeBond(int associationId) =>
      guardJni('Removing the bond', () => manager.removeBond(associationId));

  List<AssociationInfo> _associations() => guardJni(
    'Listing associations',
    () => manager.myAssociations.asDart().nonNulls.toList(),
  );

  Future<AssociationInfo?> _associate(AssociationRequest request) {
    final result = Completer<AssociationInfo?>();
    late final CompanionDeviceManager$Callback callback;
    void fail(Object error) {
      if (!result.isCompleted) result.completeError(error);
    }

    void dismissed() {
      if (!result.isCompleted) result.complete(null);
    }

    callback = CompanionDeviceManager$Callback.implement(
      onAssociationPending: (sender) async {
        if (sender == null) return;
        try {
          final code = await _activity.startIntentSender(sender);
          if (code != AndroidActivity.resultOk && !result.isCompleted) {
            result.complete(null);
          }
        } on Object catch (e) {
          fail(e);
        }
      },
      onAssociationCreated: (info) {
        if (!result.isCompleted) result.complete(info);
      },
      onFailure: (code, error) =>
          code == CompanionDeviceManager.RESULT_USER_REJECTED ||
              code == CompanionDeviceManager.RESULT_CANCELED
          ? dismissed()
          : fail(
              NativeOperationException(
                'Association failed: $error',
                nativeCode: code,
              ),
            ),
      onFailure$1: (error) => _dismissals.contains('$error')
          ? dismissed()
          : fail(NativeOperationException('Association failed: $error')),
    );
    _pending.add(callback);
    guardJni('Associating', () => manager.associate(request, callback, null));
    request.release();
    return result.future.whenComplete(() => _pending.remove(callback));
  }

  static AssociationRequest _request(CompanionRequest request) {
    final builder = AssociationRequest$Builder()
      ..setSingleDevice(request.singleDevice);
    final filter = _filter(request);
    if (filter != null) builder.addDeviceFilter(filter);
    final built = builder.build();
    builder.release();
    return built;
  }

  /// Bonded and Classic devices match a `BluetoothDeviceFilter` by address;
  /// anything else is matched in LE scans.
  static DeviceFilter<JObject?>? _filter(CompanionRequest request) {
    final le = request.service != null || request.manufacturerId != null;
    if (!le && request.nameContains == null) {
      final address = request.address;
      if (address == null) return null;
      return (BluetoothDeviceFilter$Builder()..setAddress(address.toJString()))
          .build();
    }
    final builder = BluetoothLeDeviceFilter$Builder()
      ..setScanFilter(
        androidScanFilter(
          AdvertisementFilter(
            service: request.service,
            peripheralId: request.address?.toUpperCase(),
            manufacturerId: request.manufacturerId,
            manufacturerData: request.manufacturerData,
            manufacturerDataMask: request.manufacturerDataMask,
          ),
        ),
      );
    if (request.nameContains case final text?) {
      builder.setNamePattern(_containing(text));
    }
    return builder.build();
  }

  static final _patternClass = JClass.forName('java/util/regex/Pattern');
  static final _quote = _patternClass.staticMethodId(
    'quote',
    '(Ljava/lang/String;)Ljava/lang/String;',
  );
  static final _compile = _patternClass.staticMethodId(
    'compile',
    '(Ljava/lang/String;)Ljava/util/regex/Pattern;',
  );

  /// `java.util.regex.Pattern` is only a stub in Layer 1, because its name
  /// clashes with `dart:core`, so it is compiled through raw JNI.
  static raw.Pattern _containing(String text) {
    final literal = text.toJString();
    final quoted = _quote(_patternClass, JString.type, [literal]);
    final regex = '.*${quoted.toDartString(releaseOriginal: true)}.*'
        .toJString();
    final pattern = _compile(_patternClass, raw.Pattern.type, [regex]);
    literal.release();
    regex.release();
    return pattern;
  }

  static String? _address(AssociationInfo info) =>
      info.deviceMacAddress?.toString().toUpperCase();
}

/// One `AssociationInfo`.
final class AndroidAssociation implements CompanionDeviceBackend {
  AndroidAssociation(this._info)
    : id = '${_info.id}',
      name = _info.displayName?.toString(),
      peripheralId = AndroidCompanion._address(_info);

  final AssociationInfo _info;

  @override
  final String id;

  @override
  final String? name;

  @override
  final String? peripheralId;

  @override
  CompanionHandle get native => AndroidHandle(_info);
}
