import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/mixed_topic_scroll_fixture.dart';
import 'support/topic_post_list.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  for (final inbox in [false, true]) {
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
