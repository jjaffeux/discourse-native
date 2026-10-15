import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../test/d_button_group_material_test.dart' as regressions;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  setUpAll(LiquidGlassShaders.ensureLoaded);
  testWidgets('joined controls use the live glass renderer', (_) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
  });
  regressions.main();
}
