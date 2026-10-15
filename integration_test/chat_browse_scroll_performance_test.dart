import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/chat_browse_scroll_performance_test.dart' as regressions;

// Run the real-shell scroll gestures and paint assertions on a native renderer.
// Debug mode is required for the render instrumentation.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  regressions.main();
}
