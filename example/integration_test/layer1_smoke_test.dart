import 'package:integration_test/integration_test.dart';

import 'smoke/android_smoke.dart';
import 'smoke/ios_smoke.dart';
import 'smoke/mixed_layers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  androidSmokeTests();
  iosSmokeTests();
  mixedLayerTests();
}
