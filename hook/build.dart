import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the Objective-C trampolines FFIgen generates for iOS.
///
/// The asset name matches the Dart library that declares the `@Native`
/// functions, so they resolve without an explicit asset id. Linking the
/// frameworks here is what loads them into the process.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    if (input.config.code.targetOS != OS.iOS) return;
    await CBuilder.library(
      name: 'bt_kit',
      assetName: 'src/native/ios/bindings.g.dart',
      sources: ['src/ios/bindings.g.m'],
      language: Language.objectiveC,
      flags: ['-fobjc-arc'],
      frameworks: [
        'Foundation',
        'CoreBluetooth',
        'AccessorySetupKit',
        'ExternalAccessory',
      ],
    ).run(
      input: input,
      output: output,
      logger: Logger('bt_kit')
        ..onRecord.listen((r) => stderr.writeln(r.message)),
    );
  });
}
