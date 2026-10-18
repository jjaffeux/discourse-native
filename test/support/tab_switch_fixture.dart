import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'shell_test_harness.dart';

const tabSwitchIds = ['list-a', 'list-b', 'reader-a', 'reader-b'];

Future<ShellController> pumpTabSwitchFixture(WidgetTester tester) async {
  const latest = ContentRoute(
    destination: FeedDestination(key: 'latest', mode: TopicListMode.latest),
    title: 'Topics',
    icon: DIcons.layerGroup,
  );
  const otherList = ContentRoute(
    destination: ExtensionDestination(
      'tab-switch-list',
      sourcePath: '/other.json',
    ),
    title: 'Other discussions',
    icon: DIcons.folder,
  );
  final topics = [
    for (var id = 1; id <= 100; id++)
      Topic(
        id: id,
        title: 'Discussion $id about fast navigation and reading',
        slug: 'discussion-$id',
        excerpt:
            'A discussion with formatted replies and a retained reading position.',
      ),
  ];
  await pumpShell(
    tester,
    desktop,
    instances: [instance('tabs.example')],
    api: FakeDiscourseApi(
      feeds: {'/latest.json': topics, '/other.json': topics.reversed.toList()},
      topics: {
        for (var id = 1; id <= 2; id++)
          id: topicPayload(
            id: id,
            title: topics[id - 1].title,
            posts: [
              for (var post = 1; post <= 60; post++)
                Post(
                  id: id * 1000 + post,
                  postNumber: post,
                  username: 'reader',
                  cooked:
                      '<p>Reply $post with <strong>formatted text</strong> '
                      'and a longer paragraph about switching discussions.</p>'
                      '<blockquote><p>A previous reply.</p></blockquote>'
                      '<ul><li>First point</li><li>Second point</li></ul>',
                ),
            ],
          ),
      },
    ),
    forumTabs: FakeForumTabStore([
      ForumWorkspace(
        siteUrl: 'https://tabs.example',
        accountIdentity: 'anonymous',
        activeTabId: tabSwitchIds.first,
        tabs: [
          ForumTab(
            id: 'list-a',
            rootDestinationId: latest.id,
            contentStack: const [latest],
          ),
          ForumTab(
            id: 'list-b',
            rootDestinationId: otherList.id,
            contentStack: const [otherList],
          ),
          for (var id = 1; id <= 2; id++)
            ForumTab(
              id: id == 1 ? 'reader-a' : 'reader-b',
              panel: ForumPanel.secondary,
              rootDestinationId: latest.id,
              contentStack: [
                ContentRoute.topic(
                  topicId: id,
                  slug: topics[id - 1].slug,
                  title: topics[id - 1].title,
                ),
              ],
            ),
        ],
      ),
    ]),
  );
  return ShellScope.read(tester.element(primaryMainContent));
}

Future<void> tapDocumentTab(WidgetTester tester, String id) => tester.tap(
  find.byKey(ValueKey('forum-tab-$id')),
  kind: PointerDeviceKind.mouse,
);
