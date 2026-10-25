import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/d_button_group_material_test.dart' as regressions;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('joined controls use the live glass renderer', (_) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
  });
  regressions.main();
}
