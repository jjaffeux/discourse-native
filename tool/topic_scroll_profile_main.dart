// flutter run --profile -d macos -t tool/topic_scroll_profile_main.dart
// Production topic view, synthetic long posts, no account or network data.
import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../test/support/topic_scroll_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final controller = await topicScrollController();
  final diagnostics = DiagnosticsController.start(
    persistence: MemoryDiagnosticsPersistence(),
  );
  runApp(
    TopicScrollFixture(
      controller: controller,
      diagnostics: diagnostics,
      dark: const bool.fromEnvironment('SCROLL_DARK'),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 3));
  SuperSliverList? sliver;
  ScrollableState? scrollable;
  void findList(Element element) {
    if (element.widget case final SuperSliverList list) {
      sliver = list;
      scrollable = Scrollable.maybeOf(element);
    }
    element.visitChildren(findList);
  }

  binding.rootElement!.visitChildren(findList);
  final scroll = scrollable!.widget.controller!;
  final list = sliver!.listController!;
  final capture = diagnostics.topicScrollCapture;
  const label = String.fromEnvironment('SCROLL_LABEL', defaultValue: 'capture');
  for (final name in ['first-pass', 'return-pass']) {
    capture.start(
      displayRefreshRate:
          binding.platformDispatcher.views.first.display.refreshRate,
    );
    // Repeated crossings exercise the async placeholder/settled-height cycle
    // as well as steady scrolling within a large rendered tree.
    for (final postIndex in [0, 19, 40, 19, 0, 19, 40, 19, 0]) {
      list.jumpToItem(
        index: postIndex * 2,
        scrollController: scroll,
        alignment: 0,
      );
      await binding.endOfFrame;
      for (var step = 0; step < 30; step++) {
        scroll.position.pointerScroll(40);
        await binding.endOfFrame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    capture.stop();
    final file = File(
      '${Directory.systemTemp.path}/topic-scroll-$label-$name.json',
    );
    await file.writeAsString(await capture.buildJsonReport());
    stdout.writeln('TOPIC_SCROLL_PROFILE $name ${file.path}');
    stdout.writeln(await capture.buildPerformanceReport());
  }
  stdout.writeln('TOPIC_SCROLL_PROFILE complete');
}
