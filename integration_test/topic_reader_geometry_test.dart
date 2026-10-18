import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/topic_header_scroll_motion_test.dart' as header;
import '../test/topic_progressive_html_test.dart' as progressive;
import '../test/topic_scroll_churn_test.dart' as churn;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  churn.main();
  progressive.main();
  header.main(shortTopicViewport: const Size(800, 400));
}
