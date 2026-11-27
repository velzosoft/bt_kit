import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Both layers must be importable together without a prefix, and Layer 1
/// must not shadow `dart:core`.
void main() {
  late AnalysisSession session;

  setUpAll(() {
    final root = Directory.current.absolute.path;
    final flutter = Platform.environment['FLUTTER_ROOT'];
    session = AnalysisContextCollection(
      includedPaths: ['$root/lib'],
      sdkPath: flutter == null ? null : '$flutter/bin/cache/dart-sdk',
    ).contextFor('$root/lib/bt_kit.dart').currentSession;
  });

  Future<Set<String>> exported(String uri) async {
    final result = await session.getLibraryByUri(uri) as LibraryElementResult;
    return result.element.exportNamespace.definedNames2.keys.toSet();
  }

  Future<Set<String>> own(String uri) async {
    final names = await exported(uri);
    final runtime = await exported(
      uri.endsWith('android.dart')
          ? 'package:jni/jni.dart'
          : 'package:objective_c/objective_c.dart',
    );
    return names.difference(runtime);
  }

  for (final layer1 in ['android', 'ios']) {
    test('Layer 2 and $layer1 Layer 1 export disjoint names', () async {
      final layer2 = await exported('package:bt_kit/bt_kit.dart');
      final native = await own('package:bt_kit/$layer1.dart');
      expect(layer2.intersection(native), isEmpty);
    });

    test('$layer1 Layer 1 does not shadow dart:core', () async {
      final core = await exported('dart:core');
      final native = await own('package:bt_kit/$layer1.dart');
      expect(native.intersection(core), isEmpty);
    });
  }

  test('Layer 1 hides interop plumbing', () async {
    final android = await own('package:bt_kit/android.dart');
    final ios = await own('package:bt_kit/ios.dart');
    expect(android.where((n) => n.contains('Adapter\$Listener')), isEmpty);
    expect(android, isNot(contains('ActivityBridge')));
    expect(android, isNot(contains('BackgroundDelivery')));
    expect(android.where((n) => n.startsWith('ScanThread')), isEmpty);
    expect(ios.where((n) => n.endsWith(r'$Builder')), isEmpty);
    expect(android, contains('BluetoothGattCallback'));
    expect(ios, contains('CBCentralManagerDelegate'));
  });
}
