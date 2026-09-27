import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final source in ['Topics', 'Messages']) {
    testWidgets(
      'sidebar follows the focused panel while preserving the $source source',
      (tester) async {
        const site = 'https://meta.discourse.org';
        const user = DiscourseUser(id: 7, username: 'reader');
        const publicTopic = Topic(
          id: 41,
          title: 'Public topic',
          slug: 'public-topic',
        );
        const message = Topic(
          id: 42,
          title: 'Private message',
          slug: 'private-message',
          privateMessage: true,
        );
        const trendingTopic = Topic(
          id: 43,
          title: 'Trending topic',
          slug: 'trending-topic',
        );
        final topic = source == 'Topics' ? publicTopic : message;
        await pumpShell(
          tester,
          const Size(1800, 1000),
          instances: [instance('meta.discourse.org').copyWith(user: user)],
          authenticator: FakeAuthenticator()..keys[site] = 'key',
          api: FakeDiscourseApi(
            user: user,
            feeds: const {
              '/latest.json': [publicTopic],
              '/hot.json': [trendingTopic],
              '/topics/private-messages/reader.json': [message],
            },
            topics: {
              topic.id: (
                detail: TopicDetail(
                  id: topic.id,
                  title: topic.title,
                  privateMessage: topic.privateMessage,
                  stream: const [420],
                  postsCount: 1,
                ),
                posts: const [
                  Post(
                    id: 420,
                    postNumber: 1,
                    username: 'reader',
                    cooked: '<p>Conversation body</p>',
                  ),
                ],
              ),
            },
          ),
        );
        final shell = ShellScope.read(
          tester.element(find.byType(InstanceSidebar)),
        );
        final other = source == 'Topics' ? 'Messages' : 'Topics';
        void expectActive(String label) {
          final topics = label == 'Topics';
          if (shell.currentContent?.isTopic != true) {
            final list = find.descendant(
              of: find.byKey(
                ValueKey('desktop-panel-${shell.activeTab!.panel.name}'),
              ),
              matching: find.byType(TopicListView),
            );
            expect(
              find.descendant(
                of: list,
                matching: find.text(topics ? publicTopic.title : message.title),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: list,
                matching: find.text(topics ? message.title : publicTopic.title),
              ),
              findsNothing,
            );
          }
          expect(shell.currentFeedId, topics ? 'latest' : 'messages');
          expect(
            shell.currentTopicListMode,
            topics ? TopicListMode.latest : null,
          );
          for (final destination in ['Topics', 'Messages']) {
            expect(
              tester
                  .widget<DSidebarMenuButton>(
                    find.widgetWithText(DSidebarMenuButton, destination),
                  )
                  .isActive,
              destination == label,
              reason: '$destination selection when $label is shown',
            );
          }
        }

        await tester.tap(sidebarDestination(source));
        await tester.pumpAndSettle();
        final sourceList = shell.activeTabId!;
        shell.openTopicFromList(topic);
        await tester.pumpAndSettle();
        // Ordinary navigation reads the topic in the list's own tab.
        final readerTab = shell.activeTabId!;
        expect(readerTab, sourceList);
        expectActive(source);

        // Focus a tab in the secondary panel; the sidebar navigates it.
        shell.openContentInNewTab(
          ContentRoute.newTab(),
          panel: ForumPanel.secondary,
          select: true,
        );
        await tester.pumpAndSettle();
        final otherTab = shell.activeTabId!;
        await tester.tap(sidebarDestination(other));
        await tester.pumpAndSettle();
        expect(shell.activeTabId, otherTab);
        expect(shell.activeTab?.panel, ForumPanel.secondary);
        expect(shell.selectedTabIn(ForumPanel.main)?.id, sourceList);
        expect(
          shell.currentWorkspace?.tabById(readerTab)?.currentContent.topicId,
          topic.id,
        );
        expectActive(other);

        if (other == 'Topics') {
          final panel = find.byKey(const ValueKey('desktop-panel-secondary'));
          for (final mode in [TopicListMode.popular, TopicListMode.latest]) {
            await tester.tap(
              find.descendant(
                of: panel,
                matching: find.byKey(const ValueKey('topic-list-feed-menu')),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(ValueKey('topic-list-${mode.name}')));
            await tester.pumpAndSettle();
            expect(shell.currentTopicListMode, mode);
            expect(shell.activeTabId, otherTab);
            expect(
              find.descendant(
                of: panel,
                matching: find.text(
                  mode == TopicListMode.popular
                      ? trendingTopic.title
                      : publicTopic.title,
                ),
              ),
              findsOneWidget,
            );
          }
        }

        await tester.tap(find.byKey(ValueKey('forum-tab-$sourceList')));
        await tester.pumpAndSettle();
        expect(shell.activeTabId, sourceList);
        expectActive(source);
        expect(shell.selectedTabIn(ForumPanel.secondary)?.id, otherTab);
        expect(find.byType(TopicView), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
