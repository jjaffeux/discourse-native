import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/mixed_topic_scroll_fixture.dart';
import 'support/topic_post_list.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  for (final inbox in [false, true]) {
    testWidgets('short topics keep the header visible (inbox: $inbox)', (
      tester,
    ) async {
      final controller = ShellController(
        instanceStore: FakeInstanceStore([instance('scroll.example')]),
        api: FakeDiscourseApi(
          topics: {
            7: topicPayload(
              id: 7,
              title: 'Short discussion',
              posts: [
                Post(
                  id: 1,
                  postNumber: 1,
                  username: 'reader',
                  cooked: List.filled(
                    12,
                    '<p>A paragraph in a short topic.</p>',
                  ).join(),
                ),
              ],
            ),
          },
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'short',
          title: 'Short discussion',
        ),
      );
      await controller.loadTopic(7, 'short');
      await tester.pumpWidget(
        TopicScrollFixture(controller: controller, inbox: inbox),
      );
      await tester.pumpAndSettle();
      final viewport = topicPostListFinder();
      final position = topicPostList(tester).controller!.position;
      final header = DPageSurface.headerGeometryOf(tester.element(viewport))!;
      final range = position.maxScrollExtent - position.minScrollExtent;
      expect(range, greaterThan(100));
      expect(range, lessThan(position.viewportDimension));
      for (final delta in [80.0, 80.0, -80.0]) {
        final before = position.pixels;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: topicReadingViewportRect(tester).center,
            scrollDelta: Offset(0, delta),
          ),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, isNot(before));
        expect(header.visibleExtent, header.naturalExtent);
      }
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.all());

    for (final revealing in [false, true]) {
      testWidgets(
        'paging during header motion retains the physical post anchor '
        '(inbox: $inbox, revealing: $revealing)',
        (tester) async {
          final gate = Completer<void>();
          final controller = await mixedTopicScrollController(
            api: FakeDiscourseApi(postGate: gate, topics: {}, postsById: {}),
            firstLoaded: 61,
            initialPostNumber: 71,
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            TopicScrollFixture(controller: controller, inbox: inbox),
          );
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          final viewport = topicPostListFinder();
          final post = find.byKey(const ValueKey(71));
          expect(post, findsOneWidget);
          final header = DPageSurface.headerGeometryOf(
            tester.element(viewport),
          )!;
          final viewportRect = tester.getRect(viewport);

          if (revealing) {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: topicReadingViewportRect(tester).center,
                scrollDelta: const Offset(0, 80),
              ),
            );
            for (var frame = 0; frame < 8; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            expect(header.visibleExtent, 0);
          }
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: topicReadingViewportRect(tester).center,
              scrollDelta: Offset(0, revealing ? -8 : 8),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            header.visibleExtent,
            inExclusiveRange(0, header.naturalExtent),
          );
          final top = tester.getTopLeft(post).dy;
          final loading = controller.loadEarlierPosts();
          await tester.pump();
          gate.complete();
          await loading;
          for (var frame = 0; frame < 12; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.getRect(viewport), viewportRect);
            expect(
              tester.getTopLeft(post).dy,
              closeTo(top, 1),
              reason: 'frame $frame',
            );
          }
          expect(header.visibleExtent, revealing ? header.naturalExtent : 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
