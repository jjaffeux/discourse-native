import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/cooked_html_search_highlight_test.dart' as cooked;
import '../test/topic_post_highlight_test.dart' as topic;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  cooked.main();
  topic.main();
}
