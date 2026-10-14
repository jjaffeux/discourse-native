import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/d_popover_test.dart' as popovers;

/// Checks the popup's glass compositing and shader coordinates with the
/// native renderer, including interrupted opening and closing animations.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  popovers.popoverBackdropTests();
}
