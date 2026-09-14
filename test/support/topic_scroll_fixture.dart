import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'fakes.dart';

Future<ShellController> topicScrollController() async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('scroll.example')]),
    api: FakeDiscourseApi(
      topics: {
        7: topicPayload(
          id: 7,
          title: 'Long post scrolling',
          posts: [
            for (var id = 1; id <= 60; id++)
              Post(
                id: id,
                postNumber: id,
                username: 'reader',
                createdAt: DateTime.utc(2026, 9, 1, 0, id),
                cooked: List.filled(
                  switch (id) {
                    1 => 80,
                    20 => 450,
                    _ => 3,
                  },
                  '<p>Post $id: This local paragraph exercises the production '
                  'HTML renderer with variable post heights. Scrolling back '
                  'through a long discussion should reuse recently rendered '
                  'content.</p>',
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
  await controller.load();
  controller.pushContent(
    ContentRoute.topic(
      topicId: 7,
      slug: 'long-posts',
      title: 'Long post scrolling',
    ),
  );
  await controller.loadTopic(7, 'long-posts');
  return controller;
}

class TopicScrollFixture extends StatelessWidget {
  const TopicScrollFixture({
    super.key,
    required this.controller,
    this.diagnostics,
    this.inbox = true,
    this.dark = false,
  });

  final ShellController controller;
  final DiagnosticsController? diagnostics;
  final bool inbox;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final app = ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(
          body: TopicView(inbox: inbox, route: controller.currentContent),
        ),
      ),
    );
    final diagnostics = this.diagnostics;
    return diagnostics == null
        ? app
        : DiagnosticsScope(controller: diagnostics, child: app);
  }
}
