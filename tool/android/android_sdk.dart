import 'dart:io';

import 'package:path/path.dart' as p;

/// One installed Android SDK platform, such as `android-37.0`.
final class AndroidSdkPlatform {
  AndroidSdkPlatform._(this.directory);

  factory AndroidSdkPlatform.locate(String platform) {
    final home = Platform.environment['HOME'] ?? '';
    final roots = [
      Platform.environment['ANDROID_HOME'],
      Platform.environment['ANDROID_SDK_ROOT'],
      p.join(home, 'Library', 'Android', 'sdk'),
      p.join(home, 'Android', 'Sdk'),
    ].nonNulls;
    for (final root in roots) {
      final directory = Directory(p.join(root, 'platforms', platform));
      if (directory.existsSync()) return AndroidSdkPlatform._(directory);
    }
    throw StateError(
      'Android SDK platform "$platform" was not found. '
      'Install it with: sdkmanager "platforms;$platform"',
    );
  }

  final Directory directory;

  File get androidJar => File(p.join(directory.path, 'android.jar'));

  File get stubSources => File(p.join(directory.path, 'android-stubs-src.jar'));

  File get apiVersions =>
      File(p.join(directory.path, 'data', 'api-versions.xml'));

  /// Extracts the stub sources matching [patterns] into [target].
  Future<void> extractSources(Directory target, List<String> patterns) async {
    if (target.existsSync()) target.deleteSync(recursive: true);
    target.createSync(recursive: true);
    final result = await Process.run('unzip', [
      '-q',
      '-o',
      stubSources.path,
      ...patterns,
      '-d',
      target.path,
    ]);
    if (result.exitCode != 0 && result.exitCode != 11) {
      throw ProcessException('unzip', patterns, '${result.stderr}');
    }
  }
}

/// The Flutter embedding the hand-written Java classes compile against,
/// from the Flutter SDK that runs the generator.
File flutterEmbeddingJar() {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      p.dirname(
        p.dirname(p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)))),
      );
  final jar = File(
    p.join(
      flutterRoot,
      'bin',
      'cache',
      'artifacts',
      'engine',
      'android-arm',
      'flutter.jar',
    ),
  );
  if (!jar.existsSync()) {
    throw StateError(
      'The Flutter embedding was not found at ${jar.path}. '
      'Run the generator with the Flutter SDK: flutter pub run tool/generate.dart',
    );
  }
  return jar;
}
