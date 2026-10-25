import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/plugins/boards/boards_widget_test.dart' as boards;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  boards.boardsWidgetTests(
    nativeView: true,
    onCapture: (tester, name) async {
      await binding.takeScreenshot(name);
    },
  );
}
