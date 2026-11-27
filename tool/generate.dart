import 'android/generate_android.dart';
import 'ios/generate_ios.dart';

/// Regenerates Layer 1.
///
/// ```sh
/// dart run tool/generate.dart          # both platforms
/// dart run tool/generate.dart android  # JNIgen only
/// dart run tool/generate.dart ios      # FFIgen only
/// ```
Future<void> main(List<String> args) async {
  final targets = args.isEmpty ? const {'android', 'ios'} : args.toSet();
  if (targets.contains('android')) await generateAndroid();
  if (targets.contains('ios')) await generateIos();
}
