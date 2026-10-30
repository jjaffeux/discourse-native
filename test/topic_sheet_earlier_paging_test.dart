import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/mixed_topic_scroll_fixture.dart';
import 'support/topic_post_list.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('earlier topic pages cannot trigger dismissal on $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final api = FakeDiscourseApi(postGate: gate, topics: {}, postsById: {});
      final controller = await mixedTopicScrollController(
        api: api,
        firstLoaded: 21,
        initialPostNumber: 21,
      );
      addTearDown(controller.dispose);
      var closed = false;
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: platform),
            home: DSheetViewport(
              onDismiss: () => closed = true,
              content: DSheetContent(
                side: DSheetSide.bottom,
                variant: DSheetVariant.page,
                showCloseButton: false,
                children: [
                  Expanded(
                    child: TopicView(
                      inbox: false,
                      route: controller.currentContent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      final scroll = topicPostList(tester).controller!;
      scroll.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.currentTopicHasEarlier, isTrue);
      expect(controller.loadingEarlierPosts, isTrue);
      expect(api.postFetches, isNotEmpty);
      final sheet = find.byType(DSheetContent);
      final bounds = tester.getRect(sheet);
      final drag = await tester.startGesture(
        tester.getCenter(topicPostListFinder()),
      );
      await drag.moveBy(const Offset(0, 30));
      await drag.moveBy(const Offset(0, 180));
      await drag.moveBy(const Offset(0, 180));
      await tester.pump();
      expect(tester.getRect(sheet), bounds);
      expect(closed, isFalse);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.currentPostIds.first, 1);
      expect(controller.currentTopicHasEarlier, isFalse);
      await drag.moveBy(const Offset(0, 180));
      await drag.up();
      await tester.pumpAndSettle();
      expect(closed, isFalse);

      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(topicPostListFinder(), const Offset(0, 220));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
