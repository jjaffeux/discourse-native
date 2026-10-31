import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' as fixture;
import 'support/fakes.dart';
import 'support/topic_post_list.dart';

void main() {
  for (final foot in [0.0, 24.0, 48.0]) {
    testWidgets(
      'topic footer aligns with collapsed Topics at inset $foot',
      (tester) async {
        tester.view.padding = FakeViewPadding(top: 24, bottom: foot);
        tester.view.viewPadding = FakeViewPadding(top: 24, bottom: foot);
        addTearDown(tester.view.reset);
        final shell = await fixture.pumpMobileShellFixture(
          tester,
          topic: topicPayload(
            id: 7,
            title: 'Reading a discussion',
            canCreatePost: true,
            posts: [
              for (var id = 1; id <= 80; id++)
                Post(
                  id: id,
                  postNumber: id,
                  username: 'reader',
                  cooked: '<p>Post $id discusses reading and navigation.</p>',
                ),
            ],
          ),
        );
        shell.openTopic(
          const Topic(id: 7, title: 'Reading a discussion', slug: 'reading'),
        );
        await tester.pumpAndSettle();
        final scroll = topicPostList(tester).controller!;
        scroll.jumpTo(1000);
        await tester.pumpAndSettle();
        scroll.position.pointerScroll(160);
        await tester.pumpAndSettle();
        expect(
          tester.widget<DMobileDock>(find.byType(DMobileDock)).collapsed,
          isTrue,
        );
        final topics = tester.getRect(
          find.byKey(const ValueKey('mobile-dock-reveal')),
        );
        for (final key in [
          'topic-header-bookmark-button',
          'topic-header-notification-button',
          'topic-more-actions',
          'topic-progress-button',
        ]) {
          final control = find.byKey(ValueKey(key));
          expect(control.hitTestable(), findsOneWidget);
          expect(
            tester.getCenter(control).dy,
            closeTo(topics.center.dy, .01),
            reason: '$key shares the collapsed Topics center',
          );
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
