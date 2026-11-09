import 'dart:convert';

import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_list_scroll_fixture.dart';
import 'support/topic_scroll_fixture.dart';

final class _CountingTabs implements ForumTabPersistence {
  String? value;
  int writes = 0;
  int bytes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<bool> write(String value) async {
    writes++;
    bytes += utf8.encode(value).length;
    this.value = value;
    return true;
  }

  void reset() {
    writes = 0;
    bytes = 0;
  }
}

/// Ten seconds of wheel scrolling, four ticks a second, with no pause long
/// enough for a reader to come back to any position it passes through.
Future<void> _scrollForTenSeconds(
  WidgetTester tester,
  Offset center, {
  required double delta,
}) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(center);
  for (var tick = 0; tick < 40; tick++) {
    await tester.sendEventToBinding(pointer.scroll(Offset(0, delta)));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<ForumTabSnapshot> _saved(_CountingTabs persistence) =>
    ForumTabStore(persistence: persistence).load();

void main() {
  testWidgets('scrolling a topic list writes its resting anchor once', (
    tester,
  ) async {
    final persistence = _CountingTabs();
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await topicListScrollController(
      forumTabs: ForumTabStore(persistence: persistence),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(TopicListScrollFixture(controller: controller));
    await _settle(tester);
    persistence.reset();

    await _scrollForTenSeconds(
      tester,
      tester.getCenter(find.byType(TopicListScrollFixture)),
      delta: 300,
    );
    await _settle(tester);

    debugPrint('PERF_PROOF anchor-writes list_writes=${persistence.writes}');
    debugPrint('PERF_PROOF anchor-writes list_bytes=${persistence.bytes}');
    expect(persistence.writes, 1);

    final row = controller.feedScrollRow('latest');
    expect(row, greaterThan(0), reason: 'the list must have moved');
    final saved = await _saved(persistence);
    expect(saved.workspaces.single.activeTab.anchors['latest']?.itemId, row);
  });

  testWidgets('scrolling a topic writes its resting anchor once', (
    tester,
  ) async {
    final persistence = _CountingTabs();
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await topicScrollController(
      forumTabs: ForumTabStore(persistence: persistence),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(TopicScrollFixture(controller: controller));
    await _settle(tester);
    persistence.reset();

    await _scrollForTenSeconds(
      tester,
      tester.getCenter(find.byType(TopicScrollFixture)),
      delta: 600,
    );
    await _settle(tester);

    debugPrint('PERF_PROOF anchor-writes reader_writes=${persistence.writes}');
    debugPrint('PERF_PROOF anchor-writes reader_bytes=${persistence.bytes}');
    expect(persistence.writes, 1);

    final post = controller.topicScrollPostNumber(7);
    expect(post, greaterThan(1), reason: 'the reader must have moved');
    final saved = await _saved(persistence);
    final anchor = saved.workspaces.single.activeTab.anchors['topic-7'];
    expect(anchor?.itemId, post);
    expect(anchor?.offset, controller.topicScrollPostOffset(7));
  });

  testWidgets('a reader pausing between scrolls keeps each resting anchor', (
    tester,
  ) async {
    final persistence = _CountingTabs();
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = await topicListScrollController(
      forumTabs: ForumTabStore(persistence: persistence),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(TopicListScrollFixture(controller: controller));
    await _settle(tester);
    persistence.reset();

    final center = tester.getCenter(find.byType(TopicListScrollFixture));
    final pointer = TestPointer(1, PointerDeviceKind.mouse)..hover(center);
    for (var pause = 0; pause < 3; pause++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 900)));
      await tester.pump(const Duration(milliseconds: 100));
      await _settle(tester);
      final saved = await _saved(persistence);
      expect(
        saved.workspaces.single.activeTab.anchors['latest']?.itemId,
        controller.feedScrollRow('latest'),
      );
    }

    expect(persistence.writes, 3);
  });
}
