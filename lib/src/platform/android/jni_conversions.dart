import 'dart:typed_data';

import 'package:jni/jni.dart';

import '../../core/bluetooth_uuid.dart';
import '../../core/exceptions.dart';
import '../../native/android/bindings.dart';

/// Runs a JNI call, turning Java exceptions into [BluetoothException]s.
T guardJni<T>(String operation, T Function() call) {
  try {
    return call();
  } on JThrowable catch (e) {
    final message = '$operation failed: ${e.message}';
    if (e.toString().contains('SecurityException')) {
      throw BluetoothPermissionException(const {}, message);
    }
    throw NativeOperationException(message, nativeError: e);
  }
}

/// Copies a Java `byte[]` into Dart and releases it.
Uint8List takeBytes(JByteArray? array) {
  if (array == null) return Uint8List(0);
  final bytes = Uint8List.fromList(
    Uint8List.sublistView(array.getRange(0, array.length)),
  );
  array.release();
  return bytes;
}

String? takeString(JString? string) =>
    string?.toDartString(releaseOriginal: true);

BluetoothUuid takeUuid(UUID? uuid) {
  final value = takeString(uuid?.toString$1());
  uuid?.release();
  return BluetoothUuid.parse(value!);
}

UUID javaUuid(BluetoothUuid uuid) => UUID.fromString(uuid.value.toJString())!;

/// Builds a Java object, releasing every intermediate reference.
T build<T extends JObject>(T Function(Arena arena) builder) => using(builder);
