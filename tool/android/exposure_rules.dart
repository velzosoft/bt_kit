import 'api_levels.dart';

/// How much of a Java class Layer 1 exposes.
enum Exposure {
  /// Every public member, subject to the member rules.
  full,

  /// The type only, so that signatures referring to it stay typed.
  typeOnly,
}

/// Why a member is left out of Layer 1.
enum Omission {
  deprecated('deprecated at or before the minimum API level'),
  implementedByHandlers('callback Dart implements through handlers'),
  systemCreated('constructor of a value only the system creates'),
  notInSdk('implicit constructor of a stub source; the SDK declares none');

  const Omission(this.reason);

  final String reason;
}

/// The rules that decide what the Android half of Layer 1 exposes.
///
/// Every decision is derived from the SDK itself: packages, class names,
/// modifiers and the deprecation levels in `api-versions.xml`. No member is
/// picked by hand.
final class AndroidExposureRules {
  AndroidExposureRules(this.levels, {required this.minApi});

  final ApiLevels levels;
  final ApiLevel minApi;

  /// Packages that make up the Bluetooth API surface.
  static const bluetoothPackages = [
    'android.bluetooth',
    'android.bluetooth.le',
    'android.companion',
  ];

  /// Package trees whose subpackages also belong to the surface.
  static const bluetoothPackageTrees = ['android.ranging'];

  /// Platform classes an app must call to obtain, configure or receive
  /// Bluetooth objects.
  static const supportClasses = [
    'android.app.PendingIntent',
    'android.content.BroadcastReceiver',
    'android.content.Context',
    'android.content.Intent',
    'android.content.IntentFilter',
    'android.content.pm.PackageInfo',
    'android.content.pm.PackageManager',
    'android.os.Build',
    'android.os.Handler',
    'android.os.Looper',
    'android.os.OutcomeReceiver',
    'android.os.ParcelUuid',
    'android.util.SparseArray',
    'java.io.InputStream',
    'java.io.OutputStream',
    'java.util.UUID',
    'java.util.concurrent.Executor',
    'java.util.function.Consumer',
  ];

  static const _nonBluetoothPackageSegments = {'uwb', 'wifi'};
  static final _nonBluetoothClassNames = RegExp(r'^(Uwb|Wifi|Rtt|DlTdoa)');
  static final _systemCreatedValues = RegExp(r'(Result|Status|Event)$');

  /// Input for the binding generator: whole packages plus support classes.
  List<String> get inputs => [...packages, ...supportClasses];

  /// Every package of the surface, including those inside package trees.
  late final List<String> packages = _packages();

  List<String> _packages() {
    final packages = {...bluetoothPackages};
    for (final className in levels.classNames) {
      final package = className.substring(0, className.lastIndexOf('.'));
      if (bluetoothPackageTrees.any(
        (tree) => package == tree || package.startsWith('$tree.'),
      )) {
        packages.add(package);
      }
    }
    return packages.toList()..sort();
  }

  bool isInScope(String binaryName) {
    final package = binaryName.substring(0, binaryName.lastIndexOf('.'));
    final outer = binaryName.split(r'$').first;
    return packages.contains(package) || supportClasses.contains(outer);
  }

  /// Source-jar patterns to extract for [inputs].
  List<String> get sourcePatterns => [
    for (final package in bluetoothPackages)
      '${package.replaceAll('.', '/')}/*.java',
    for (final tree in bluetoothPackageTrees) '${tree.replaceAll('.', '/')}/*',
    for (final type in supportClasses)
      if (!type.startsWith('java.')) '${type.replaceAll('.', '/')}.java',
  ];

  Exposure classExposure(String binaryName) {
    final history = levels.classHistory(binaryName);
    if (history != null && history.deprecatedAtOrBefore(minApi)) {
      return Exposure.typeOnly;
    }
    return isNonBluetooth(binaryName) ? Exposure.typeOnly : Exposure.full;
  }

  /// UWB and Wi-Fi APIs that the ranging package pulls in by reference.
  bool isNonBluetooth(String binaryName) {
    final segments = binaryName.split('.');
    final simpleName = segments.removeLast();
    return segments.any(_nonBluetoothPackageSegments.contains) ||
        _nonBluetoothClassNames.hasMatch(simpleName);
  }

  /// Values only the system creates, such as `ScanResult` or `BondStatus`.
  bool isSystemCreatedValue(String binaryName, {required bool isFinal}) =>
      isFinal && _systemCreatedValues.hasMatch(binaryName.split(r'$').last);

  Omission? fieldOmission(String binaryName, String field) =>
      (levels.fieldHistory(binaryName, field)?.deprecatedAtOrBefore(minApi) ??
          false)
      ? Omission.deprecated
      : null;

  Omission? methodOmission(
    String binaryName,
    String name,
    int arity, {
    required bool isFinalClass,
    required bool isForwardedCallback,
  }) {
    if (isForwardedCallback) return Omission.implementedByHandlers;
    if (name == '<init>') {
      if (isSystemCreatedValue(binaryName, isFinal: isFinalClass)) {
        return Omission.systemCreated;
      }
      if (levels.classHistory(binaryName) != null &&
          levels.overloads(binaryName, name, arity).isEmpty) {
        return Omission.notInSdk;
      }
    }
    return includesMethod(binaryName, name, arity) ? null : Omission.deprecated;
  }

  /// Whether a method survives the deprecation rule.
  ///
  /// Overloads are matched by name and arity. A method is dropped only when
  /// every matching overload is deprecated, so the rule never removes a
  /// non-deprecated overload.
  bool includesMethod(String binaryName, String name, int arity) {
    final overloads = levels.overloads(binaryName, name, arity);
    return overloads.isEmpty ||
        !overloads.every((o) => o.history.deprecatedAtOrBefore(minApi));
  }
}
