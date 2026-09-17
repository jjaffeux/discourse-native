// Run with flutter run --profile -d macos -t tool/topic_list_scroll_profile_main.dart.
// Uses the production topic list with deterministic, local-only data.
import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:flutter/widgets.dart';

import '../test/support/topic_list_scroll_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  const mode = String.fromEnvironment('LIST_MODE', defaultValue: 'compact');
  const events = bool.fromEnvironment('LIST_EVENTS', defaultValue: true);
  const assignments = bool.fromEnvironment(
    'LIST_ASSIGNMENTS',
    defaultValue: true,
  );
  final controller = await topicListScrollController(
    count: 1000,
    mode: TopicListDisplayMode.values.byName(mode),
    events: events,
    assignments: assignments,
  );
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
  // A Dart ensureSemantics() handle alone does not activate macOS's native
  // accessibility bridge. For AX reproductions, wait for a platform request.
  if (const bool.fromEnvironment('LIST_REQUIRE_ACCESSIBILITY')) {
    final waiting = Stopwatch()..start();
    while (!binding.platformDispatcher.semanticsEnabled) {
      if (waiting.elapsed > const Duration(seconds: 30)) {
        throw StateError(
          'Native accessibility was not enabled. Enable it before profiling.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  await Future<void>.delayed(const Duration(seconds: 3));
  ScrollableState? scrollable;
  void findScrollable(Element element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      final candidate = element.state as ScrollableState;
      if (candidate.position.axis == Axis.vertical) scrollable ??= candidate;
    }
    element.visitChildren(findScrollable);
  }

  (listKey.currentContext! as Element).visitChildren(findScrollable);
  final position = scrollable!.position;
  final capture = diagnostics.topicScrollCapture;
  stdout.writeln(
    'TOPIC_LIST_PROFILE mode=$mode events=$events assignments=$assignments',
  );
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
    const label = String.fromEnvironment(
      'PROFILE_LABEL',
      defaultValue: 'local',
    );
    final file = File(
      '${Directory.systemTemp.path}/topic-list-$label-$name.json',
    );
    await file.writeAsString(report);
    stdout.writeln('TOPIC_LIST_PROFILE $name ${file.path}');
    stdout.writeln(await capture.buildPerformanceReport());
  }
  stdout.writeln('TOPIC_LIST_PROFILE complete');
}
