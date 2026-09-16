// flutter run --profile -d macos -t tool/chat_scroll_profile_main.dart
// Mounts the real channel with deterministic local messages and fake transport.
import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:flutter/widgets.dart';

import '../test/support/chat_scroll_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final controller = await chatScrollController(
    count: int.parse(
      _option(
        'SCROLL_MESSAGES',
        const String.fromEnvironment('SCROLL_MESSAGES', defaultValue: '500'),
      ),
    ),
    directMessage:
        _option('SCROLL_DM', const String.fromEnvironment('SCROLL_DM')) ==
        'true',
    group:
        _option('SCROLL_GROUP', const String.fromEnvironment('SCROLL_GROUP')) ==
        'true',
  );
  final diagnostics = DiagnosticsController.start(
    persistence: MemoryDiagnosticsPersistence(),
  );
  runApp(
    ChatScrollFixture(
      controller: controller,
      diagnostics: diagnostics,
      width: double.parse(
        _option(
          'SCROLL_WIDTH',
          const String.fromEnvironment('SCROLL_WIDTH', defaultValue: '800'),
        ),
      ),
      dark:
          _option('SCROLL_DARK', const String.fromEnvironment('SCROLL_DARK')) ==
          'true',
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  ScrollableState? scrollable;
  void findScrollable(Element element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final state = element.state as ScrollableState;
      if (axisDirectionToAxis(state.axisDirection) == Axis.vertical) {
        scrollable ??= state;
      }
    }
    element.visitChildren(findScrollable);
  }

  binding.rootElement!.visitChildren(findScrollable);
  final position = scrollable!.position;
  final capture = diagnostics.topicScrollCapture;
  final label = _option(
    'SCROLL_LABEL',
    const String.fromEnvironment('SCROLL_LABEL', defaultValue: 'capture'),
  );
  for (final (name, delta, steps) in [
    ('steady', 10.0, 360),
    ('fast', 1200.0, 12),
    ('return', -1200.0, 12),
  ]) {
    capture.start(
      displayRefreshRate:
          binding.platformDispatcher.views.first.display.refreshRate,
    );
    for (var step = 0; step < steps; step++) {
      position.pointerScroll(delta);
      await binding.endOfFrame;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    capture.stop();
    final file = File(
      '${Directory.systemTemp.path}/chat-scroll-$label-$name.json',
    );
    await file.writeAsString(await capture.buildJsonReport());
    stdout.writeln('CHAT_SCROLL_PROFILE $name ${file.path}');
    stdout.writeln(await capture.buildPerformanceReport());
  }
  stdout.writeln('CHAT_SCROLL_PROFILE complete');
}

// Runtime overrides let the same native build compare all fixture layouts.
String _option(String name, String fallback) =>
    Platform.environment[name] ?? fallback;
