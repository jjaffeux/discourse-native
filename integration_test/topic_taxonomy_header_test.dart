import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../test/topic_taxonomy_header_test.dart' as headers;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUpAll(LiquidGlass.precache);
  headers.main(
    nativeView: true,
    onCapture: (tester, name) async {
      await binding.takeScreenshot(name);
    },
  );
}
