// flutter run --profile -d macos -t tool/topic_scroll_profile_main.dart
// Production topic view, synthetic long posts, no account or network data.
import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../test/support/mixed_topic_scroll_fixture.dart';
import '../test/support/topic_scroll_fixture.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  const mixed = bool.fromEnvironment('SCROLL_MIXED');
  const prepend = bool.fromEnvironment('SCROLL_PREPEND');
  final controller = mixed || prepend
      ? await mixedTopicScrollController(
          firstLoaded: prepend ? 95 : 1,
          initialPostNumber: prepend ? 105 : null,
        )
      : await topicScrollController();
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
  if (prepend) {
    for (final offset in [6, 9, 12, 10]) {
      list.jumpToItem(
        index: (offset + 1) * 2,
        scrollController: scroll,
        alignment: 0,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  final capture = diagnostics.topicScrollCapture;
  const label = String.fromEnvironment('SCROLL_LABEL', defaultValue: 'capture');
  for (final name in ['first-pass', 'return-pass']) {
    capture.start(
      displayRefreshRate:
          binding.platformDispatcher.views.first.display.refreshRate,
    );
    // Repeated crossings exercise the async placeholder/settled-height cycle
    // as well as steady scrolling within a large rendered tree.
    if (prepend) {
      await controller.loadEarlierPosts();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final direction in [-1, 1]) {
        for (var step = 0; step < 60; step++) {
          scroll.position.pointerScroll(direction * 40);
          await binding.endOfFrame;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } else if (mixed) {
      for (final direction in [1, -1, 1, -1]) {
        for (var step = 0; step < 120; step++) {
          scroll.position.pointerScroll(direction * 80);
          await binding.endOfFrame;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } else {
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
