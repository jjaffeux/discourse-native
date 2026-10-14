import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/glass_compositing_test.dart' as audit;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('native renderer supports live glass', (_) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
  });
  audit.glassCompositingTests(native: true);
}
