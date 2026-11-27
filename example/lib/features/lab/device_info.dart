import 'dart:io';

import 'package:bt_kit/android.dart' as android;
import 'package:bt_kit/ios.dart' as ios;

/// The phone the Lab runs on, for reports and the reference's Info value.
abstract final class DeviceInfo {
  static Map<String, Object?> describe() => {
    'platform': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    if (Platform.isAndroid) ..._android(),
    if (Platform.isIOS) 'iosVersion': ios.osVersion.toString(),
    'dart': Platform.version.split(' ').first,
    'processors': Platform.numberOfProcessors,
  };

  /// Such as "Android 16 (API 36) Google Pixel 9" or "iOS 26.1.0".
  static String summary() {
    if (Platform.isIOS) return 'iOS ${ios.osVersion}';
    if (!Platform.isAndroid) return Platform.operatingSystem;
    final info = _android();
    return 'Android ${info['release']} (API ${info['sdkInt']}) '
        '${info['manufacturer']} ${info['model']}';
  }

  static Map<String, Object?> _android() => {
    'sdkInt': android.Build$VERSION.SDK_INT,
    'release': _string(android.Build$VERSION.RELEASE),
    'manufacturer': _string(android.Build.MANUFACTURER),
    'model': _string(android.Build.MODEL),
  };

  static String? _string(android.JString? value) =>
      value?.toDartString(releaseOriginal: true);
}
