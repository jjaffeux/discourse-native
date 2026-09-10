import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'fakes.dart';

Future<ShellController> topicListScrollController({int count = 500}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('scroll.example')]),
    api: FakeDiscourseApi(
      feeds: {
        '/latest.json': [
          for (var id = 1; id <= count; id++)
            Topic(
              id: id,
              title: id.isEven
                  ? 'Topic $id with a longer title that can wrap onto a second line'
                  : 'Topic $id',
              slug: 'topic-$id',
              categoryId: 2,
              tags: const [
                TopicTag(name: 'performance'),
                TopicTag(name: 'support'),
              ],
              views: id * 10,
              postsCount: id % 30 + 1,
              bumpedAt: DateTime.utc(2026, 9, 1),
              closed: id % 7 == 0,
              bookmarked: id % 11 == 0,
            ),
        ],
      },
      categoryList: const [
        TopicCategory(id: 1, name: 'General', color: '0088CC'),
        TopicCategory(
          id: 2,
          name: 'Development',
          color: '00AA88',
          parentCategoryId: 1,
        ),
      ],
    ),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  await controller.loadFeed('latest');
  final feed = controller.currentFeed!;
  if (feed.topicIds.length != count ||
      feed.topicIds.any(
        (id) =>
            controller.store.read<Topic>(controller.currentInstance!.url, id) ==
            null,
      )) {
    throw StateError('The scroll fixture must retain all requested topics.');
  }
  return controller;
}

class TopicListScrollFixture extends StatelessWidget {
  const TopicListScrollFixture({
    super.key,
    required this.controller,
    required this.diagnostics,
    this.listKey,
    this.width = 800,
  });

  final ShellController controller;
  final DiagnosticsController diagnostics;
  final GlobalKey? listKey;
  final double width;

  @override
  Widget build(BuildContext context) => DiagnosticsScope(
    controller: diagnostics,
    child: ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 600,
              child: TopicListView(key: listKey, feed: controller.currentFeed!),
            ),
          ),
        ),
      ),
    ),
  );
}
