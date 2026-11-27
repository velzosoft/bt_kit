// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:jnigen/jnigen.dart';
import 'package:jnigen/src/summary/summary.dart' show getSummary;
import 'package:jnigen/tools.dart' show buildSummarizerIfNotExists;
import 'package:logging/logging.dart';

import '../common/library_exports.dart';
import 'android_sdk.dart';
import 'api_levels.dart';
import 'callback_classes.dart';
import 'callback_facades.dart';
import 'exposure_rules.dart';
import 'exposure_visitors.dart';
import 'inventory.dart';
import 'java_adapters.dart';

/// The SDK the bindings are generated from: the newest final Android release.
const sdkPlatform = 'android-37.0';

/// The oldest Android release the package supports.
const minApi = ApiLevel(33);

const _bindings = 'lib/src/native/android/bindings.g.dart';
const _entryPoint = 'lib/android.dart';
const _internalBarrel = 'lib/src/native/android/bindings.dart';
const _inventory = 'doc/inventory/android.md';
const _javaSources = 'android/src/main/java';
const _adapters = '$_javaSources/dev/btkit/adapters';
const _plumbing = [
  'dev.btkit.ActivityBridge',
  'dev.btkit.BackgroundDelivery',
  'dev.btkit.ScanThread',
];

Future<void> generateAndroid() async {
  final sdk = AndroidSdkPlatform.locate(sdkPlatform);
  final rules = AndroidExposureRules(
    ApiLevels.load(sdk.apiVersions),
    minApi: minApi,
  );
  final sources = Directory('.dart_tool/bt_kit/$sdkPlatform-sources');
  await sdk.extractSources(sources, rules.sourcePatterns);

  Input input(List<String> classes) => Input(
    classes: classes,
    sourcePath: [
      Uri.directory('tool/android/annotations'),
      sources.uri,
      Uri.directory(_javaSources),
    ],
    classPath: [sdk.androidJar.uri, flutterEmbeddingJar().uri],
  );

  await buildSummarizerIfNotExists();
  final summary = await getSummary(
    JniGenerator(input: input(rules.inputs), output: _output),
  );
  final callbacks = CallbackClass.find(summary, rules);
  writeJavaAdapters(Directory(_adapters), callbacks);

  final classes = [
    ...rules.inputs,
    ..._plumbing,
    for (final c in callbacks) c.adapterBinaryName,
  ];
  ExposureVisitors exposure() => ExposureVisitors(
    rules,
    finalClasses: {
      for (final decl in summary.decls.values)
        if (decl.isFinal) decl.binaryName,
    },
    forwardedCallbacks: {
      for (final c in callbacks)
        for (final m in c.callbacks)
          '${c.binaryName}#${m.name}/${m.params.length}',
    },
  );

  await _generate(input(classes), exposure().visitors);
  final facades = callbackFacades(
    File(_bindings).readAsStringSync(),
    callbacks,
  );
  final finalPass = exposure();
  await _generate(input(classes), finalPass.visitors, facades);

  await _writeLibraries(callbacks);
  writeAndroidInventory(
    File(_inventory),
    summary: summary,
    rules: rules,
    callbacks: callbacks,
    exposure: finalPass,
    sdkPlatform: sdkPlatform,
  );
}

final _output = Output(
  dart: DartOutput(
    path: Uri.file(_bindings),
    structure: OutputStructure.singleFile,
  ),
  generateStubs: true,
);

Future<void> _generate(
  Input input,
  List<Visitor> visitors, [
  Map<String, String> customClassBody = const {},
]) => JniGenerator(
  input: input,
  output: _output,
  nullability: const NullabilityAnnotations(
    nonNull: ['android.annotation.NonNull'],
    nullable: ['android.annotation.Nullable'],
  ),
  visitors: visitors,
  customClassBody: customClassBody,
).generate(logger: _logger);

final _logger = Logger('jnigen')
  ..onRecord.listen((record) {
    if (record.level >= Level.WARNING) stderr.writeln(record.message);
  });

/// Writes `lib/android.dart`, which exports the bindings without the
/// adapters, listeners, bridge, background delivery and scan thread that
/// only exist for interop, and the internal barrel Layer 2 imports.
Future<void> _writeLibraries(List<CallbackClass> callbacks) async {
  final plumbing = [
    for (final c in callbacks) c.adapterName,
    for (final name in _plumbing) name.split('.').last,
  ];
  final names = declaredNames(File(_bindings));
  final collisions = await nameCollisions(File(_bindings), names);
  await writeExports(
    File(_entryPoint),
    header: _entryPointDoc,
    exports: [
      "export 'package:jni/jni.dart';",
      "export 'package:jni_flutter/jni_flutter.dart'\n"
          '    show androidActivity, androidApplicationContext;',
    ],
    bindings: 'src/native/android/bindings.g.dart',
    hidden: {
      ...collisions,
      for (final name in names)
        if (plumbing.any((p) => name.replaceFirst(r'$', '').startsWith(p)))
          name,
    },
  );
  await writeExports(
    File(_internalBarrel),
    header: '\n/// Layer 1 as Layer 2 sees it, plumbing included.\nlibrary;\n',
    exports: const [],
    bindings: 'bindings.g.dart',
    hidden: collisions,
  );
}

const _entryPointDoc = '''

/// Layer 1 for Android: direct bindings to the Android Bluetooth APIs.
///
/// Every public class of `android.bluetooth`, `android.bluetooth.le`,
/// `android.companion` and `android.ranging` is available here, together
/// with the platform types needed to drive them. Abstract callback classes
/// are implemented with their `implement` factory.
///
/// Stubs whose names would shadow `dart:core`, such as `java.time.Duration`,
/// are not exported.
library;
''';
