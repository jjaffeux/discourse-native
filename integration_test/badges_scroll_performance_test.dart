import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/badges_scroll_performance_test.dart' as regressions;

// Debug mode preserves the paint instrumentation on the native renderer.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  regressions.main(
    nativeView: true,
    onCapture: const bool.fromEnvironment('CAPTURE_BADGES')
        ? (name) async {
            await binding.takeScreenshot(name);
          }
        : null,
  );
}
