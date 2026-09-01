import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';

void main() {
  group('topicContextEyeline', () {
    test('stays at the top before the final viewport', () {
      expect(
        topicContextEyeline(
          viewportExtent: 600,
          scrollOffset: 1200,
          maxScrollExtent: 3000,
          postStreamBottom: 2400,
          hasMore: false,
        ),
        1,
      );
    });

    test(
      'crosses the viewport midpoint halfway through the final viewport',
      () {
        expect(
          topicContextEyeline(
            viewportExtent: 600,
            scrollOffset: 2700,
            maxScrollExtent: 3000,
            postStreamBottom: 900,
            hasMore: false,
          ),
          closeTo(300.25, 0.01),
        );
      },
    );

    test('reaches the stream bottom at the end', () {
      expect(
        topicContextEyeline(
          viewportExtent: 600,
          scrollOffset: 3000,
          maxScrollExtent: 3000,
          postStreamBottom: 600,
          hasMore: false,
        ),
        599.5,
      );
    });
  });

  testWidgets(
    'publishes the current topic and the web-compatible post neighborhood',
    (tester) async {
      final site = instance('meta.example');
      final controller = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      final posts = [
        for (var index = 0; index < 12; index++)
          Post(
            id: 101 + index,
            postNumber: index + 1,
            username: 'reader',
            cooked: '<p>Post ${index + 1}</p>',
            hidden: index == 1 || index == 5,
            deletedAt: index == 3 ? DateTime.utc(2026) : null,
          ),
      ];
      controller.store
        ..put(
          site.url,
          TopicDetail(
            id: 31,
            title: 'Visible context',
            stream: [for (final post in posts) post.id],
            postsCount: posts.length,
          ),
        )
        ..putAll(site.url, posts);
      controller.pushContent(
        ContentRoute.topic(
          topicId: 31,
          slug: 'visible-context',
          title: 'Visible context',
        ),
      );

      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: TopicView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final list = tester.widget<SuperListView>(find.byType(SuperListView));
      final range = list.listController!.visibleRange!;
      final firstPostChild = range.$1.isEven ? range.$1 : range.$1 + 1;
      final currentIndex = firstPostChild ~/ 2;
      final current = posts[currentIndex];

      int? eligibleNeighbor(int from, int step) {
        for (
          var index = from;
          index >= 0 && index < posts.length;
          index += step
        ) {
          final post = posts[index];
          if (!post.hidden && !post.isDeleted) return post.id;
        }
        return null;
      }

      final context = controller.visibleTopicContext;
      expect(context?.siteUrl, site.url);
      expect(context?.topicId, 31);
      expect(context?.postIds, [
        ?eligibleNeighbor(currentIndex - 1, -1),
        current.id,
        ?eligibleNeighbor(currentIndex + 1, 1),
      ]);

      await tester.drag(find.byType(SuperListView), const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(controller.visibleTopicContext?.postIds, [
        posts[10].id,
        posts[11].id,
      ]);

      controller.pushContent(ContentRoute.topicList(TopicListMode.latest));
      expect(controller.visibleTopicContext, isNull);
    },
  );

  testWidgets('clears a topic context when its view is disposed', (
    tester,
  ) async {
    final site = instance('meta.example');
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        const TopicDetail(
          id: 31,
          title: 'Visible context',
          stream: [101],
          postsCount: 1,
        ),
      )
      ..put(
        site.url,
        const Post(
          id: 101,
          postNumber: 1,
          username: 'reader',
          cooked: '<p>Post 1</p>',
        ),
      );
    controller.pushContent(
      ContentRoute.topic(
        topicId: 31,
        slug: 'visible-context',
        title: 'Visible context',
      ),
    );

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: TopicView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.visibleTopicContext, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.visibleTopicContext, isNull);
  });
}
