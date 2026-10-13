import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/desktop_panels.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'desktop title action follows the focused panel and topic progress floats',
    (tester) async {
      const user = DiscourseUser(
        id: 3,
        username: 'reader',
        canCreateTopic: true,
        canSendPrivateMessages: true,
      );
      const topic = Topic(id: 42, title: 'A topic', slug: 'a-topic');
      final api = FakeDiscourseApi(
        user: user,
        feeds: const {
          '/latest.json': [topic],
        },
        creatableFeedPaths: const {'/latest.json'},
        topics: {
          42: (
            detail: const TopicDetail(
              id: 42,
              title: 'A topic',
              stream: [1, 2],
              postsCount: 2,
              canCreatePost: true,
            ),
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'reader',
                cooked: '<p>First post</p>',
              ),
              Post(
                id: 2,
                postNumber: 2,
                username: 'sam',
                cooked: '<p>Second post</p>',
              ),
            ],
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'key',
      );
      final shell = ShellScope.read(
        tester.element(find.byType(MainContent).first),
      );
      final main = shell.activeTabId!;
      final title = find.byType(ShellTitleBar);
      var split = find.byKey(const ValueKey('panel-split-view-secondary'));
      final mainPanel = find.byKey(const ValueKey('desktop-panel-main'));
      final secondaryPanel = find.byKey(
        const ValueKey('desktop-panel-secondary'),
      );
      final panels = find.byType(DesktopPanels);
      var splitIcon = find.descendant(
        of: split,
        matching: find.byType(DLayoutGlyph),
      );
      expect(tester.getSize(split), const Size.square(36));
      expect(tester.getSize(splitIcon), const Size(20, 15));
      expect(tester.widget<DLayoutGlyph>(splitIcon).mainVisible, isTrue);
      expect(tester.widget<DToggle>(split).density, DToggleDensity.splitView);
      expect(tester.widget<DToggle>(split).pressed, isTrue);
      final splitWidth = tester.getSize(mainPanel).width;
      await tester.tap(split);
      await tester.pumpAndSettle();
      split = find.byKey(const ValueKey('panel-split-view-main'));
      splitIcon = find.descendant(
        of: split,
        matching: find.byType(DLayoutGlyph),
      );
      expect(tester.widget<DToggle>(split).pressed, isFalse);
      expect(tester.widget<DLayoutGlyph>(splitIcon).secondaryVisible, isFalse);
      expect(secondaryPanel, findsNothing);
      expect(find.byKey(const ValueKey('panel-rail-secondary')), findsNothing);
      expect(
        find.byKey(const ValueKey('main-panel-resize-handle')),
        findsNothing,
      );
      expect(tester.getRect(mainPanel), tester.getRect(panels));
      await tester.tap(split);
      await tester.pumpAndSettle();
      split = find.byKey(const ValueKey('panel-split-view-secondary'));
      expect(tester.widget<DToggle>(split).pressed, isTrue);
      expect(secondaryPanel, findsOneWidget);
      expect(tester.getSize(mainPanel).width, splitWidth);
      await tester.tap(find.byKey(const ValueKey('panel-split-view-main')));
      await tester.pumpAndSettle();
      expect(tester.widget<DToggle>(split).pressed, isFalse);
      expect(find.byKey(const ValueKey('panel-rail-main')), findsNothing);
      expect(tester.getRect(secondaryPanel), tester.getRect(panels));
      await tester.tap(split);
      await tester.pumpAndSettle();
      expect(tester.widget<DToggle>(split).pressed, isTrue);
      expect(find.byKey(const ValueKey('panel-rail-main')), findsNothing);
      expect(tester.getSize(mainPanel).width, splitWidth);
      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(TopicCreateButton.buttonKey),
        ),
        findsOneWidget,
      );
      shell.createTab(panel: ForumPanel.secondary);
      shell.openTopicFromList(topic);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(const ValueKey('title-bar-reply')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('topic-bottom-bar')), findsNothing);
      expect(
        tester
            .widget<TopicProgressPopover>(find.byType(TopicProgressPopover))
            .floating,
        isTrue,
      );
      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(const ValueKey('title-bar-reply')),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(TopicCreateButton.buttonKey),
        ),
        findsOneWidget,
      );
      shell.pushContent(ContentRoute.messages());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(const ValueKey('new-message-button')),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: title,
          matching: find.byKey(const ValueKey('new-message-button')),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.visibleComposer, isNotNull);
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(const ValueKey('new-message-button')),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('composer-minimize')));
      await tester.pumpAndSettle();
      // The composer occupies the secondary workspace. Minimizing it focuses
      // that panel's topic; the title action follows that focused reader.
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(const ValueKey('title-bar-reply')),
        ),
        findsOneWidget,
      );
      shell.selectTab(main);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: title,
          matching: find.byKey(const ValueKey('new-message-button')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
