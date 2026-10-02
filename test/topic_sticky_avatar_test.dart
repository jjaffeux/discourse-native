import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_post_list.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  for (final inbox in [true, false]) {
    testWidgets('desktop avatar stays within its post (inbox: $inbox)', (
      tester,
    ) async {
      final controller = await _pump(tester, inbox: inbox);
      final scroll = topicPostList(tester).controller!;
      final slot = find.byKey(const ValueKey('topic-sticky-avatar-1'));
      final avatar = find.descendant(of: slot, matching: find.byType(DAvatar));
      final html = tester.element(find.byType(CookedHtml).first);
      var htmlRebuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (identical(element, html)) htmlRebuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      for (final offset in [400.0, 600.0, 450.0]) {
        scroll.jumpTo(offset);
        await tester.pump();
        expect(
          tester.getTopLeft(avatar).dy,
          closeTo(topicReadingViewportRect(tester).top + 14, .01),
        );
      }
      expect(htmlRebuilds, 0);
      // The first list item also owns a topic map. It must not prolong the
      // avatar's sticky range after the post's footer has scrolled away.
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey(1))).dy,
        greaterThan(tester.getBottomLeft(slot).dy + 16),
      );
      final viewportTop = topicReadingViewportRect(tester).top;
      scroll.jumpTo(
        scroll.offset + tester.getBottomLeft(slot).dy - viewportTop - 20,
      );
      await tester.pump();
      expect(tester.getBottomLeft(avatar).dy, closeTo(viewportTop + 20, .01));

      scroll.jumpTo(450);
      await tester.pumpAndSettle();
      controller.setTopicPostSelectionEnabled(
        'https://scroll.example',
        7,
        true,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(avatar).dy,
        closeTo(topicReadingViewportRect(tester).top + 14, .01),
      );
      // A real user scroll also retracts the topic header.
      await tester.drag(topicPostListFinder(), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(avatar).dy,
        closeTo(topicReadingViewportRect(tester).top + 14, .01),
      );
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('user-card-surface')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop gutter follows RTL without covering the post body', (
    tester,
  ) async {
    await _pump(tester, direction: TextDirection.rtl);
    topicPostList(tester).controller!.jumpTo(400);
    await tester.pump();
    final slot = find.byKey(const ValueKey('topic-sticky-avatar-1'));
    final avatar = find.descendant(of: slot, matching: find.byType(DAvatar));
    final body = find.byType(CookedHtml).first;
    expect(
      tester.getTopLeft(avatar).dx,
      greaterThan(tester.getTopRight(body).dx),
    );
    expect(
      tester.getTopLeft(avatar).dy,
      closeTo(topicReadingViewportRect(tester).top + 14, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop avatar returns with a retained post after a distant jump',
    (tester) async {
      await _pump(tester);
      final list = topicPostList(tester);
      final originalHtml = tester.element(find.byType(CookedHtml).first);
      list.listController!.jumpToItem(
        index: 60,
        scrollController: list.controller!,
        alignment: 0,
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey(1)), findsNothing);
      expect(originalHtml.mounted, isTrue);

      list.listController!.jumpToItem(
        index: 0,
        scrollController: list.controller!,
        alignment: 0,
      );
      await tester.pumpAndSettle();
      list.controller!.jumpTo(400);
      await tester.pump();
      final avatar = find.descendant(
        of: find.byKey(const ValueKey('topic-sticky-avatar-1')),
        matching: find.byType(DAvatar),
      );
      expect(tester.element(find.byType(CookedHtml).first), same(originalHtml));
      expect(
        tester.getTopLeft(avatar).dy,
        closeTo(topicReadingViewportRect(tester).top + 14, .01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform avatars keep scrolling with the mobile header', (
      tester,
    ) async {
      await _pump(tester, platform: platform);
      expect(find.byType(DSticky), findsNothing);
      final avatar = find
          .descendant(
            of: find.byKey(const ValueKey(1)),
            matching: find.byType(DAvatar),
          )
          .first;
      final before = tester.getTopLeft(avatar).dy;
      topicPostList(tester).controller!.jumpTo(400);
      await tester.pump();
      expect(tester.getTopLeft(avatar).dy, closeTo(before - 400, .01));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<ShellController> _pump(
  WidgetTester tester, {
  bool inbox = true,
  TargetPlatform platform = TargetPlatform.macOS,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = await topicScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: TopicView(inbox: inbox, route: controller.currentContent),
          ),
        ),
      ),
    ),
  );
  final rendered = find.byWidgetPredicate(
    (widget) =>
        widget is RichText && widget.text.toPlainText().contains('Post 1:'),
  );
  final elapsed = Stopwatch()..start();
  while (rendered.evaluate().isEmpty &&
      elapsed.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(rendered, findsWidgets);
  await tester.pumpAndSettle();
  return controller;
}
