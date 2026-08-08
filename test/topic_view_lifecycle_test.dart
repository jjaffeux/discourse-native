import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('scrolling records the latest read post and reopening uses it', (
    tester,
  ) async {
    final site = instance('meta.example');
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
    final authenticator = FakeAuthenticator()..keys[site.url] = 'key';
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    _storeFullTopic(controller, site.url, topicId: 1, firstPostId: 100);
    controller.store.put(
      site.url,
      const Topic(
        id: 1,
        title: 'One',
        slug: 'one',
        unreadPosts: 29,
        lastReadPostNumber: 1,
        highestPostNumber: 30,
      ),
    );
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    // Pointer drags are clipped by the test viewport, so walk the lazy list
    // down in a few screen-sized gestures instead of using one huge offset.
    for (var i = 0; i < 6; i++) {
      await tester.drag(vertical.first, const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(api.topicReadsRecorded.last, (topicId: 1, postNumber: 30));
    final row = controller.store.read<Topic>(site.url, 1)!;
    expect(row.lastReadPostNumber, 30);
    expect(row.hasUnread, isFalse);

    expect(controller.handleBack(), isTrue);
    controller.openTopic(row);

    expect(controller.currentContent?.postNumber, 30);
  });

  testWidgets(
    'records the visible range after programmatic scrolling lays out',
    (tester) async {
      final site = instance('meta.example');
      final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
      final authenticator = FakeAuthenticator()..keys[site.url] = 'key';
      final controller = ShellController(
        instanceStore: FakeInstanceStore([site]),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      _storeFullTopic(controller, site.url, topicId: 1, firstPostId: 100);
      controller.store.putAll(site.url, [
        for (var id = 100; id < 130; id++)
          Post(
            id: id,
            postNumber: id - 99,
            username: 'sam',
            cooked: List.filled(12, '<p>Long post $id</p>').join(),
          ),
      ]);
      controller.store.put(
        site.url,
        const Topic(
          id: 1,
          title: 'One',
          slug: 'one',
          unreadPosts: 29,
          lastReadPostNumber: 1,
          highestPostNumber: 30,
        ),
      );
      controller.pushContent(
        ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
      );

      await tester.pumpWidget(_topicView(controller));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        controller.store.read<Topic>(site.url, 1)!.lastReadPostNumber,
        lessThan(30),
      );
      api.topicReadsRecorded.clear();

      final list = tester.widget<SuperListView>(find.byType(SuperListView));
      final scroll = list.controller!;
      final initialRange = list.listController!.visibleRange;
      final initialPixels = scroll.position.pixels;
      final listener = tester.widget<NotificationListener<ScrollNotification>>(
        find
            .descendant(
              of: find.byType(TopicView),
              matching: find.byType(NotificationListener<ScrollNotification>),
            )
            .first,
      );
      listener.onNotification!(
        ScrollUpdateNotification(
          metrics: FixedScrollMetrics(
            minScrollExtent: scroll.position.minScrollExtent,
            maxScrollExtent: scroll.position.maxScrollExtent,
            pixels: scroll.position.pixels,
            viewportDimension: scroll.position.viewportDimension,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1,
          ),
          context: tester.element(find.byType(TopicView)),
        ),
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();

      final range = list.listController!.visibleRange!;
      expect(scroll.position.pixels, greaterThan(initialPixels));
      expect(range, isNot(initialRange));
      final highestVisibleChild = range.$2.isEven ? range.$2 : range.$2 - 1;
      final highestVisibleRow = highestVisibleChild ~/ 2;
      await tester.pump(const Duration(milliseconds: 600));

      expect(api.topicReadsRecorded.last, (
        topicId: 1,
        postNumber: highestVisibleRow + 1,
      ));
    },
  );

  testWidgets('each topic starts with its own scroll position', (tester) async {
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
    await tester.pump();
    _storeFullTopic(controller, site.url, topicId: 1, firstPostId: 100);
    _storeFullTopic(controller, site.url, topicId: 2, firstPostId: 200);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
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
    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.drag(vertical.first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(vertical.first).position.pixels,
      greaterThan(0),
    );

    controller.pushContent(
      ContentRoute.topic(topicId: 2, slug: 'two', title: 'Two'),
    );
    await tester.pump();

    expect(tester.state<ScrollableState>(vertical.first).position.pixels, 0);
  });

  testWidgets('a numbered topic route reveals that post on first layout', (
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
    _storeFullTopic(controller, site.url, topicId: 1, firstPostId: 100);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 12),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();

    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    expect(
      tester.state<ScrollableState>(vertical.first).position.pixels,
      greaterThan(0),
    );
    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    final range = list.listController!.visibleRange!;
    expect((range.$1 + 1) ~/ 2, lessThanOrEqualTo(11));
    expect(range.$2 ~/ 2, greaterThanOrEqualTo(11));
  });

  testWidgets('a queued page request cannot cross a topic switch', (
    tester,
  ) async {
    final api = _PostsApi();
    final site = instance('meta.example');
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pump();

    _storeTopic(controller, site.url, topicId: 1, postId: 101);
    _storeTopic(controller, site.url, topicId: 2, postId: 201);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    var showView = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return showView ? const TopicView() : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.pushContent(
        ContentRoute.topic(topicId: 2, slug: 'two', title: 'Two'),
      );
      rebuild(() => showView = false);
    });
    rebuild(() => showView = true);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.postPageTopics, isNot(contains(2)));
  });

  testWidgets('a queued page request stays with its shell controller', (
    tester,
  ) async {
    final firstApi = _PostsApi();
    final secondApi = _PostsApi();
    final site = instance('meta.example');
    final first = _controller(site, firstApi);
    final second = _controller(site, secondApi);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait([first.load(), second.load()]);

    for (final controller in [first, second]) {
      _storePagedTopic(controller, site.url, topicId: 1, firstPostId: 100);
      controller.pushContent(
        ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
      );
    }

    await tester.pumpWidget(_topicView(first));
    await tester.pumpAndSettle();
    expect(firstApi.postPageTopics, isEmpty);

    final listener = tester.widget<NotificationListener<ScrollNotification>>(
      find
          .descendant(
            of: find.byType(TopicView),
            matching: find.byType(NotificationListener<ScrollNotification>),
          )
          .first,
    );
    listener.onNotification!(
      ScrollUpdateNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 100,
          pixels: 100,
          viewportDimension: 100,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1,
        ),
        context: tester.element(find.byType(TopicView)),
      ),
    );

    await tester.pumpWidget(_topicView(second));
    await tester.pump();

    expect(firstApi.postPageTopics, isEmpty);
    expect(secondApi.postPageTopics, isEmpty);
  });

  test('an around-post window pages in both directions', () async {
    final site = instance('meta.example');
    final allPosts = {
      for (var number = 1; number <= 100; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: '<p>Post $number</p>',
        ),
    };
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: allPosts,
    );
    final controller = _controller(site, api);
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        TopicDetail(
          id: 1,
          title: 'One',
          stream: [for (var id = 1; id <= 100; id++) id],
          postsCount: 100,
        ),
      )
      ..putAll(site.url, [for (var id = 40; id <= 59; id++) allPosts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 45),
    );

    await controller.loadMorePosts(batchSize: 5);
    await controller.loadEarlierPosts(batchSize: 5);

    expect(api.postFetches, [
      [60, 61, 62, 63, 64],
      [35, 36, 37, 38, 39],
    ]);
    expect(controller.currentPostIds, [for (var id = 35; id <= 64; id++) id]);
  });
}

ShellController _controller(DiscourseInstance site, FakeDiscourseApi api) =>
    ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );

Widget _topicView(ShellController controller) => ShellScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light,
    home: const Scaffold(body: TopicView()),
  ),
);

void _storeFullTopic(
  ShellController controller,
  String siteUrl, {
  required int topicId,
  required int firstPostId,
}) {
  final posts = [
    for (var id = firstPostId; id < firstPostId + 30; id++)
      Post(
        id: id,
        postNumber: id - firstPostId + 1,
        username: 'sam',
        cooked: '<p>Post $id</p>',
      ),
  ];
  controller.store
    ..put(
      siteUrl,
      TopicDetail(
        id: topicId,
        title: 'Topic $topicId',
        stream: [for (final post in posts) post.id],
        postsCount: posts.length,
      ),
    )
    ..putAll(siteUrl, posts);
}

void _storeTopic(
  ShellController controller,
  String siteUrl, {
  required int topicId,
  required int postId,
}) {
  controller.store
    ..put(
      siteUrl,
      TopicDetail(
        id: topicId,
        title: 'Topic $topicId',
        stream: [postId, postId + 1],
        postsCount: 2,
      ),
    )
    ..put(
      siteUrl,
      Post(
        id: postId,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>Post $postId</p>',
      ),
    );
}

void _storePagedTopic(
  ShellController controller,
  String siteUrl, {
  required int topicId,
  required int firstPostId,
}) {
  final loaded = [
    for (var id = firstPostId; id < firstPostId + 100; id++)
      Post(
        id: id,
        postNumber: id - firstPostId + 1,
        username: 'sam',
        cooked: '<p>Post $id</p>',
      ),
  ];
  controller.store
    ..put(
      siteUrl,
      TopicDetail(
        id: topicId,
        title: 'Topic $topicId',
        stream: [for (var id = firstPostId; id < firstPostId + 120; id++) id],
        postsCount: 120,
      ),
    )
    ..putAll(siteUrl, loaded);
}

final class _PostsApi extends FakeDiscourseApi {
  _PostsApi() : super(feeds: const {'/latest.json': []});

  final List<int> postPageTopics = [];

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    postPageTopics.add(topicId);
    return const [];
  }
}
