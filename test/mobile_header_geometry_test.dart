import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mobile_shell_test.dart' show pumpMobileShellFixture;
import 'support/fakes.dart';
import 'support/topic_post_list.dart';

void main() {
  for (final (width, scale) in [
    (390.0, 1.0),
    (320.0, 1.0),
    (390.0, 2.0),
    (320.0, 2.0),
  ]) {
    testWidgets(
      'mobile header keeps one height across pages at $width and ${scale}x',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final shell = await pumpMobileShellFixture(
          tester,
          size: Size(width, 844),
          topic: topicPayload(
            id: 7,
            title: 'A topic with taxonomy in its bar',
            categoryId: 1,
            tags: const [TopicTag(id: 1, name: 'how-to')],
            posts: [
              for (var id = 1; id <= 30; id++)
                Post(
                  id: id,
                  postNumber: id,
                  username: 'reader',
                  cooked:
                      '<p>A discussion post with enough height to scroll.</p>',
                ),
            ],
          ),
          sidebarCategories: const [
            TopicCategory(id: 1, name: 'Support', color: '0088cc'),
          ],
        );
        final header = find.byKey(const ValueKey('mobile-header'));
        final home = find.byKey(const ValueKey('mobile-home-button'));
        final initial = tester.getRect(header);
        final homeCenter = tester.getCenter(home);
        if (scale == 1) expect(initial.height, 52);
        void expectStable(String state) {
          expect(tester.getRect(header), initial, reason: state);
          expect(tester.getCenter(home), homeCenter, reason: state);
          expect(tester.takeException(), isNull, reason: state);
        }

        await tester.tap(find.byKey(const ValueKey('topic-card-7')));
        await tester.pumpAndSettle();
        expectStable('topic at the top');
        topicPostList(tester).controller!.jumpTo(600);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mobile-page-title')).hitTestable(),
          findsOneWidget,
        );
        expectStable('scrolled topic with metadata');
        final barTitle = find.descendant(
          of: find.byKey(const ValueKey('mobile-page-title')),
          matching: find.text('A topic with taxonomy in its bar'),
        );
        expect(
          MediaQuery.textScalerOf(tester.element(barTitle)).scale(17),
          closeTo(17 * scale, .01),
        );
        shell.toggleMobileSidebar();
        await tester.pumpAndSettle();
        expectStable('open navigation');
        shell.closeMobileSidebar();
        await tester.pumpAndSettle();
        expectStable('closed navigation');
        shell.handleBack();
        await tester.pumpAndSettle();
        expectStable('returned to the list');
        final chat = shell.pluginSession.require(chatShellService);
        for (final (name, open) in [
          ('chats', () => chat.openChats()),
          ('channel browser', () => chat.openBrowseChannels()),
          ('threads', () => chat.openMyThreads()),
        ]) {
          open();
          await tester.pumpAndSettle();
          expectStable(name);
        }
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }
}
