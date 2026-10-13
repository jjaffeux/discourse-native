import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/composer_opening_test.dart' as opening;

/// Runs opening contracts with the native renderer and reports content-free
/// layout, paint, and focus milestones. These are debug diagnostics, not
/// raster-frame or device-latency measurements. Use PROFILE_LABEL to distinguish
/// captures, and avoid concurrent builds when comparing elapsed times.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  opening.main(profile: true);
}
