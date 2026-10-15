import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/command_presentation_rendering_test.dart' as command;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('native renderer supports live glass', (_) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
  });
  command.commandPresentationRenderingTests(native: true);
}
