import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/primary_action_capsule_test.dart' as capsule;

/// Runs the same contracts with the native renderer. Set
/// PRIMARY_ACTION_CAPTURE_DIR with --dart-define to export rendered chrome.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  capsule.main();
}
