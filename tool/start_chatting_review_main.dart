// Offline fixture of the production start-chatting dialog. No account writes.
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:flutter/widgets.dart';

import '../test/support/start_chatting_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final shell = await startChattingShell(StartChattingApi());
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(StartChattingFixture(shell: shell));
}
