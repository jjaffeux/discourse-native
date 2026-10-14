import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/user_card_popover_test.dart' as cards;

/// Verifies the cached card's first glass frame and transition on Impeller.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('native renderer supports the glass backdrop shader', (_) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
  });
  // Keep sampled frames inside the entrance on slower native test runners.
  cards.userCardBackdropTests(slowAnimations: true);
}
