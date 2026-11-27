import 'package:jni/jni.dart';

import '../../models/permission.dart';
import '../../native/android/bindings.dart';
import 'android_activity.dart';
import 'jni_conversions.dart';

/// Android runtime permissions for Bluetooth (API 31 and later).
///
/// Android cannot tell "never asked" from "denied permanently" before the
/// first request, so a permission the app has not requested in this process
/// reports [PermissionStatus.notDetermined] until it does.
///
/// Scan results reach an app whose manifest declares `BLUETOOTH_SCAN`
/// without `neverForLocation` only while it holds the location permission.
final class AndroidPermissions {
  AndroidPermissions(this._context, this._activity);

  static const _names = {
    BluetoothPermission.scan: 'android.permission.BLUETOOTH_SCAN',
    BluetoothPermission.connect: 'android.permission.BLUETOOTH_CONNECT',
    BluetoothPermission.advertise: 'android.permission.BLUETOOTH_ADVERTISE',
    BluetoothPermission.ranging: 'android.permission.RANGING',
    BluetoothPermission.location: 'android.permission.ACCESS_FINE_LOCATION',
  };

  final Context _context;
  final AndroidActivity _activity;
  final _requested = <BluetoothPermission>{};
  late final Map<String, int> _declared = _declaredPermissions();

  /// Whether the manifest declares `BLUETOOTH_SCAN` without disavowing
  /// location.
  late final bool scanNeedsLocation =
      switch (_declared[_names[BluetoothPermission.scan]]) {
        final flags? =>
          flags & PackageInfo.REQUESTED_PERMISSION_NEVER_FOR_LOCATION == 0,
        null => false,
      };

  Map<BluetoothPermission, PermissionStatus> check(
    Set<BluetoothPermission> permissions,
  ) => {for (final permission in permissions) permission: _status(permission)};

  Future<Map<BluetoothPermission, PermissionStatus>> request(
    Set<BluetoothPermission> permissions,
  ) async {
    final askable = [
      for (final MapEntry(key: permission, value: status) in check(
        permissions,
      ).entries)
        if (status == PermissionStatus.notDetermined ||
            status == PermissionStatus.denied)
          permission,
    ];
    if (askable.isNotEmpty) {
      await _activity.requestPermissions([for (final p in askable) _names[p]!]);
      _requested.addAll(askable);
    }
    return check(permissions);
  }

  PermissionStatus _status(BluetoothPermission permission) {
    final name = _names[permission]!;
    if (!_declared.containsKey(name)) return PermissionStatus.notDeclared;
    final granted =
        _context.checkSelfPermission(name.toJString()) ==
        PackageManager.PERMISSION_GRANTED;
    if (granted) return PermissionStatus.granted;
    if (_activity.shouldShowRationale(name)) return PermissionStatus.denied;
    return _requested.contains(permission)
        ? PermissionStatus.permanentlyDenied
        : PermissionStatus.notDetermined;
  }

  /// Each declared permission with its `requestedPermissionsFlags`.
  Map<String, int> _declaredPermissions() => guardJni(
    'Reading the manifest',
    () {
      final info = _context.packageManager!.getPackageInfo$3(
        _context.packageName!,
        PackageManager.GET_PERMISSIONS,
      );
      final names = info?.requestedPermissions?.asDart() ?? const <JString?>[];
      final flags = info?.requestedPermissionsFlags;
      final declared = <String, int>{};
      for (final (i, name) in names.indexed) {
        final permission = takeString(name);
        if (permission == null) continue;
        declared[permission] = flags != null && i < flags.length ? flags[i] : 0;
      }
      flags?.release();
      return declared;
    },
  );
}
