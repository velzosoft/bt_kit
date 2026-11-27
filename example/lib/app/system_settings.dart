import 'dart:ffi';
import 'dart:io';

import 'package:bt_kit/android.dart' as android;
import 'package:bt_kit/ios.dart' as ios;

/// Opens this app's page in the system settings, where the user can grant
/// the Bluetooth permission.
///
/// Uses direct native interop like the rest of the app: Layer 1 on Android,
/// and the Objective-C runtime on iOS.
abstract final class SystemSettings {
  static void openAppSettings() {
    if (Platform.isAndroid) _openAndroid();
    if (Platform.isIOS) _openIos();
  }

  static void _openAndroid() {
    final context = android.androidApplicationContext.as(android.Context.type);
    final package = context.packageName!.toDartString(releaseOriginal: true);
    final intent = android.Intent.parseUri('package:$package'.toJString(), 0)!;
    intent
        .setAction('android.settings.APPLICATION_DETAILS_SETTINGS'.toJString())
        .release();
    intent.addFlags(android.Intent.FLAG_ACTIVITY_NEW_TASK).release();
    context.startActivity(intent);
    intent.release();
  }

  /// `[UIApplication.sharedApplication openURL:options:completionHandler:]`
  /// with `UIApplicationOpenSettingsURLString`.
  static void _openIos() {
    final url = ios.NSURL.URLWithString('app-settings:'.toNSString());
    if (url == null) return;
    final application = _sharedApplication(
      ios.getClass('UIApplication'),
      ios.registerName('sharedApplication'),
    );
    _openUrl(
      application,
      ios.registerName('openURL:options:completionHandler:'),
      url.ref.pointer,
      ios.NSDictionary.dictionary().ref.pointer,
      nullptr,
    );
  }

  static final _sharedApplication = ios.msgSendPointer
      .cast<
        NativeFunction<
          ios.ObjectPtr Function(ios.ObjectPtr, Pointer<ios.ObjCSelector>)
        >
      >()
      .asFunction<
        ios.ObjectPtr Function(ios.ObjectPtr, Pointer<ios.ObjCSelector>)
      >();

  static final _openUrl = ios.msgSendPointer
      .cast<
        NativeFunction<
          Void Function(
            ios.ObjectPtr,
            Pointer<ios.ObjCSelector>,
            ios.ObjectPtr,
            ios.ObjectPtr,
            Pointer<Void>,
          )
        >
      >()
      .asFunction<
        void Function(
          ios.ObjectPtr,
          Pointer<ios.ObjCSelector>,
          ios.ObjectPtr,
          ios.ObjectPtr,
          Pointer<Void>,
        )
      >();
}
