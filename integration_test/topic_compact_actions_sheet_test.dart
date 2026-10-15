import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/topic_compact_actions_sheet_test.dart' as sheets;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  final screenshots = <Map<String, Object>>[];
  sheets.topicCompactActionsSheetTests(
    native: true,
    onCapture: (tester, name) async {
      final bytes = await sheets.captureTopicCompactSheet(
        tester,
        tester.view.physicalSize / tester.view.devicePixelRatio,
      );
      screenshots.add({'screenshotName': name, 'bytes': bytes});
      binding.reportData = {'screenshots': screenshots};
    },
  );
}
