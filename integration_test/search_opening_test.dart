import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/global_search_presentation_test.dart' as search;

/// Runs search route contracts with the native renderer. Select the mobile
/// opening cases with --name; these checks do not measure device frame times.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  search.main(useDeviceMetrics: true);
}
