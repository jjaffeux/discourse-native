// Run with flutter run --profile -d macos -t tool/topic_list_scroll_profile_main.dart.
// Uses the production topic list with deterministic, local-only data.
import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:flutter/widgets.dart';

import '../test/support/topic_list_scroll_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final controller = await topicListScrollController(count: 1000);
  final diagnostics = DiagnosticsController.start(
    persistence: MemoryDiagnosticsPersistence(),
  );
  final listKey = GlobalKey();
  runApp(
    TopicListScrollFixture(
      controller: controller,
      diagnostics: diagnostics,
      listKey: listKey,
      width: const int.fromEnvironment(
        'SCROLL_WIDTH',
        defaultValue: 800,
      ).toDouble(),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  ScrollableState? scrollable;
  void findScrollable(Element element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      scrollable ??= element.state as ScrollableState;
    }
    element.visitChildren(findScrollable);
  }

  (listKey.currentContext! as Element).visitChildren(findScrollable);
  final position = scrollable!.position;
  final capture = diagnostics.topicScrollCapture;
  for (final (name, delta, steps) in [
    ('steady', 40.0, 180),
    ('fast', 1200.0, 40),
    ('return', -1200.0, 40),
  ]) {
    capture.start(
      displayRefreshRate:
          binding.platformDispatcher.views.first.display.refreshRate,
    );
    for (var step = 0; step < steps; step++) {
      position.pointerScroll(delta);
      await binding.endOfFrame;
    }
    // Engine timings arrive in batches after the last scroll frame.
    await Future<void>.delayed(const Duration(seconds: 1));
    capture.stop();
    final report = await capture.buildJsonReport();
    final file = File('${Directory.systemTemp.path}/topic-list-$name.json');
    await file.writeAsString(report);
    stdout.writeln('TOPIC_LIST_PROFILE $name ${file.path}');
    stdout.writeln(await capture.buildPerformanceReport());
  }
  stdout.writeln('TOPIC_LIST_PROFILE complete');
}
