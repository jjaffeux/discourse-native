import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/scrollbar_header_drag_test.dart' as grip;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  setUpAll(() async {
    await const MethodChannel(
      'org.discourse.native/window',
    ).invokeMethod<void>('dismissLaunchScreen');
  });
  grip.main();
}
