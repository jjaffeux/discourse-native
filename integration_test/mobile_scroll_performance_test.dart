import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/mobile_scroll_performance_test.dart' as regressions;

// Run the same real-shell gestures and paint assertions on a native renderer.
// Use debug mode: the render instrumentation is intentionally assertion-only.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  regressions.main();
}
