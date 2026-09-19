import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
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
      'sidebar follows the split list while a $source reader stays open',
      (tester) async {
        const site = 'https://meta.discourse.org';
        const user = DiscourseUser(id: 7, username: 'reader');
        final topic = Topic(
          id: 42,
          title: 'Retained conversation',
          slug: 'retained-conversation',
          privateMessage: source == 'Messages',
        );
        await pumpShell(
          tester,
          const Size(1800, 1000),
          instances: [instance('meta.discourse.org').copyWith(user: user)],
          authenticator: FakeAuthenticator()..keys[site] = 'key',
          api: FakeDiscourseApi(
            user: user,
            feeds: {
              '/latest.json': [if (!topic.privateMessage) topic],
              '/topics/private-messages/reader.json': [
                if (topic.privateMessage) topic,
              ],
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
        final readerTab = shell.activeTabId!;
        final readerState = tester.state(find.byType(TopicView));
        expectActive(source);

        await tester.tap(sidebarDestination(other));
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.isMessages, other == 'Messages');
        expect(shell.activeTabId, readerTab);
        expect(tester.state(find.byType(TopicView)), same(readerState));
        expectActive(other);

        shell.createTab();
        await tester.pumpAndSettle();
        final newList = shell.listPanelTab!.id;
        await tester.tap(sidebarDestination(source));
        await tester.pumpAndSettle();
        expectActive(source);
        for (final (id, label) in [(sourceList, other), (newList, source)]) {
          await tester.tap(find.byKey(ValueKey('forum-tab-item-$id')));
          await tester.pumpAndSettle();
          expect(shell.activeTabId, readerTab);
          expectActive(label);
        }

        await tester.tap(sidebarDestination(other));
        await tester.pumpAndSettle();
        expectActive(other);
        await tester.tap(find.byTooltip('Keep topic tabs with the list').first);
        await tester.pumpAndSettle();
        expect(shell.splitTopicPanels, isFalse);
        expectActive(source);
        await tester.tap(sidebarDestination(other));
        await tester.pumpAndSettle();
        expectActive(other);
        await tester.tap(find.byKey(ValueKey('forum-tab-item-$readerTab')));
        await tester.pumpAndSettle();
        expectActive(source);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  }
}
