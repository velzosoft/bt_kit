import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:jni/jni.dart';

import '../../core/exceptions.dart';
import '../../native/android/bindings.dart';

/// Starts activities of this Flutter engine and returns their results.
///
/// Permission prompts and the enable-Bluetooth dialog report back through
/// `Activity` callbacks, which only a plugin class can receive; the
/// `ActivityBridge` adapter forwards them here.
final class AndroidActivity {
  AndroidActivity() : _engineId = _currentEngineId() {
    ActivityBridge.setListener(
      _engineId,
      ActivityBridge$Listener.implement(
        $ActivityBridge$Listener(
          onRequestPermissionsResult: _onPermissionsResult,
          onRequestPermissionsResult$async: true,
          onActivityResult: (code, resultCode, data) =>
              _pending.remove(code)?.complete(resultCode),
          onActivityResult$async: true,
        ),
      ),
    );
  }

  static const resultOk = -1;

  final int _engineId;
  final _pending = <int, Completer<Object?>>{};
  var _nextCode = ActivityBridge.FIRST_REQUEST_CODE;

  /// Shows the permission prompt; returns whether each permission is
  /// granted afterwards.
  Future<Map<String, bool>> requestPermissions(List<String> permissions) async {
    final code = _reserveCode();
    final names = JArray.of(JString.type, [
      for (final permission in permissions) permission.toJString(),
    ]);
    final started = ActivityBridge.requestPermissions(_engineId, names, code);
    names.release();
    final result = await _await(code, started);
    return result as Map<String, bool>;
  }

  bool shouldShowRationale(String permission) =>
      ActivityBridge.shouldShowRequestPermissionRationale(
        _engineId,
        permission.toJString(),
      );

  /// Starts [intent] and returns the activity's result code.
  Future<int> startForResult(Intent intent) async {
    final code = _reserveCode();
    final started = ActivityBridge.startActivityForResult(
      _engineId,
      intent,
      code,
    );
    return await _await(code, started) as int;
  }

  /// Starts the activity behind [sender] and returns its result code.
  Future<int> startIntentSender(IntentSender sender) async {
    final code = _reserveCode();
    final started = ActivityBridge.startIntentSenderForResult(
      _engineId,
      sender,
      code,
    );
    return await _await(code, started) as int;
  }

  Future<Object?> _await(int code, bool started) {
    if (!started) {
      throw const NativeOperationException(
        'No Android activity is attached to this Flutter engine',
      );
    }
    return (_pending[code] = Completer<Object?>()).future;
  }

  int _reserveCode() {
    final code = _nextCode;
    _nextCode = code == ActivityBridge.LAST_REQUEST_CODE
        ? ActivityBridge.FIRST_REQUEST_CODE
        : code + 1;
    return code;
  }

  void _onPermissionsResult(
    int code,
    JArray<JString?>? permissions,
    JIntArray? grantResults,
  ) {
    final completer = _pending.remove(code);
    if (completer == null) return;
    final names = [
      for (final name in permissions?.asDart() ?? const <JString?>[])
        name?.toDartString(releaseOriginal: true) ?? '',
    ];
    final grants = grantResults?.getRange(0, grantResults.length) ?? const [];
    completer.complete({
      for (var i = 0; i < names.length && i < grants.length; i++)
        names[i]: grants[i] == PackageManager.PERMISSION_GRANTED,
    });
  }

  static int _currentEngineId() {
    final engineId = PlatformDispatcher.instance.engineId;
    if (engineId == null) {
      throw UnsupportedError(
        'bt_kit must run on an isolate that belongs to a Flutter engine',
      );
    }
    return engineId;
  }
}
