import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../test/forum_settings_page_test.dart' as regressions;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(() async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    await LiquidGlassShaders.ensureLoaded();
  });
  regressions.mobileSettingsPanelClipTests();
}
