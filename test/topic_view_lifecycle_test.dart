import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/loading_skeleton.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
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

  testWidgets('reopening restores the position within a long final post', (
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
    controller.store
      ..put(
        site.url,
        const TopicDetail(id: 1, title: 'One', stream: [100], postsCount: 1),
      )
      ..putAll(site.url, [
        Post(
          id: 100,
          postNumber: 1,
          username: 'sam',
          cooked: List.filled(80, '<p>A long final post</p>').join(),
        ),
      ])
      ..put(
        site.url,
        const Topic(
          id: 1,
          title: 'One',
          slug: 'one',
          unreadPosts: 1,
          highestPostNumber: 1,
        ),
      );
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    var list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      list.controller!.position.pixels,
      closeTo(list.controller!.position.maxScrollExtent, 1),
    );
    expect(api.topicReadsRecorded.last, (topicId: 1, postNumber: 1));
    final row = controller.store.read<Topic>(site.url, 1)!;
    expect(row.hasUnread, isFalse);

    expect(controller.handleBack(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    controller.openTopic(row);
    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();

    list = tester.widget<SuperListView>(find.byType(SuperListView));
    expect(
      list.controller!.position.pixels,
      closeTo(list.controller!.position.maxScrollExtent, 1),
    );
  });

  testWidgets(
    'backgrounding from a video-only final post keeps its read receipt',
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
      addTearDown(() => _resumeLifecycle(tester));
      await controller.load();
      controller.store
        ..put(
          site.url,
          const TopicDetail(id: 1, title: 'One', stream: [100], postsCount: 1),
        )
        ..put(
          site.url,
          const Post(
            id: 100,
            postNumber: 1,
            username: 'sam',
            cooked: '''
<div class="youtube-onebox lazy-video-container"
  data-video-id="dQw4w9WgXcQ"
  data-video-title="Only a video"
  data-provider-name="youtube">
  <a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"
     class="video-thumbnail"></a>
</div>
''',
          ),
        )
        ..put(
          site.url,
          const Topic(
            id: 1,
            title: 'One',
            slug: 'one',
            unreadPosts: 1,
            highestPostNumber: 1,
          ),
        );
      controller.pushContent(
        ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
      );

      await tester.pumpWidget(_topicView(controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(YoutubeVideo), findsOneWidget);
      expect(api.topicReadsRecorded, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump();

      expect(api.topicReadsRecorded, [(topicId: 1, postNumber: 1)]);
    },
  );

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

  testWidgets('showing the recommendations panel keeps one scroll attachment', (
    tester,
  ) async {
    final site = instance('meta.example');
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
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
          id: 1,
          title: 'One',
          stream: [1, 2, 3, 4, 5, 6],
          postsCount: 6,
          recommendations: TopicRecommendations(
            sources: [
              TopicRecommendationSource(
                definition: coreSuggestedTopicRecommendationSource,
                topics: [Topic(id: 2, title: 'Suggested', slug: 'suggested')],
              ),
            ],
          ),
        ),
      )
      ..putAll(site.url, [
        for (var id = 3; id <= 5; id++)
          Post(
            id: id,
            postNumber: id,
            username: 'sam',
            cooked: '<p>Post $id</p>',
          ),
      ]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 5),
    );

    var showRecommendationsPanel = false;
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
                return TopicView(
                  showRecommendationsPanel: showRecommendationsPanel,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.currentTopicHasEarlier, isTrue);
    expect(controller.currentTopicHasMore, isTrue);
    final scroll = tester
        .widget<SuperListView>(find.byType(SuperListView))
        .controller!;
    expect(scroll.positions, hasLength(1));
    final position = scroll.position;

    rebuild(() => showRecommendationsPanel = true);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('topic-recommendations-panel')),
      findsOneWidget,
    );
    expect(scroll.positions, hasLength(1));
    expect(scroll.position, same(position));

    await tester.pumpAndSettle();
    rebuild(() => showRecommendationsPanel = false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('topic-recommendations-panel')),
      findsNothing,
    );
    expect(scroll.positions, hasLength(1));
    expect(scroll.position, same(position));
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

  testWidgets('topic progress replaces the saved viewport anchor', (
    tester,
  ) async {
    final site = instance('meta.example');
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
    final controller = ShellController(
      instanceStore: FakeInstanceStore([site]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    _storeFullTopic(controller, site.url, topicId: 1, firstPostId: 100);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );
    controller.saveTopicScrollPost(1, 26);

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(125)), findsOneWidget);

    expect(await controller.jumpToCurrentTopicIndex(12), isTrue);
    await tester.pumpAndSettle();

    expect(controller.currentContent?.postNumber, 12);
    expect(controller.topicScrollPostNumber(1), 12);
    expect(find.byKey(const ValueKey(111)), findsOneWidget);
    expect(api.topicPostNumbersOpened, isEmpty);
  });

  testWidgets('a prepend between initial jumps still reveals the named post', (
    tester,
  ) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 100; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: List.filled(8, '<p>Long post $number</p>').join(),
        ),
    };
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: posts,
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
      ..putAll(site.url, [for (var id = 61; id <= 100; id++) posts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 80),
    );

    // pumpWidget runs the first estimated jump and queues the corrected one.
    await tester.pumpWidget(_topicView(controller));
    await controller.loadEarlierPosts();
    await tester.pump();
    await tester.pump();

    expect(api.postFetches, [
      [for (var id = 41; id <= 60; id++) id],
    ]);
    final viewport = tester.getRect(find.byType(SuperListView));
    final target = find.byKey(const ValueKey(80));
    expect(target, findsOneWidget);
    expect(tester.getTopLeft(target).dy, closeTo(viewport.top, 1));
  });

  testWidgets(
    'scrolling near the top loads earlier posts without moving the viewport',
    (tester) async {
      final site = instance('meta.example');
      final posts = {
        for (var number = 1; number <= 100; number++)
          number: Post(
            id: number,
            postNumber: number,
            username: 'sam',
            cooked: List.filled(
              number <= 60 ? number % 5 + 1 : 8,
              '<p>Long post $number</p>',
            ).join(),
          ),
      };
      final postGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        postsById: posts,
        postGate: postGate,
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
        ..putAll(site.url, [for (var id = 61; id <= 100; id++) posts[id]!]);
      controller.pushContent(
        ContentRoute.topic(
          topicId: 1,
          slug: 'one',
          title: 'One',
          postNumber: 80,
        ),
      );

      await tester.pumpWidget(_topicView(controller));
      await tester.pumpAndSettle();

      final list = tester.widget<SuperListView>(find.byType(SuperListView));
      final scroll = list.controller!;
      expect(scroll.position.extentBefore, greaterThan(900));
      expect(api.postFetches, isEmpty);
      expect(find.text('Load earlier posts'), findsNothing);

      scroll.jumpTo(800);
      await tester.pump();
      await tester.pump();

      expect(api.postFetches, [
        [for (var id = 41; id <= 60; id++) id],
      ]);

      // More scroll notifications while the request is in flight must not
      // enqueue another copy of the same page.
      scroll.jumpTo(700);
      await tester.pump();
      expect(api.postFetches, hasLength(1));

      final viewport = tester.getRect(find.byType(SuperListView));
      Finder? anchor;
      for (var id = 61; id <= 100; id++) {
        final candidate = find.byKey(ValueKey(id));
        if (candidate.evaluate().isEmpty) continue;
        final rect = tester.getRect(candidate);
        if (rect.top >= viewport.top && rect.bottom <= viewport.bottom) {
          anchor = candidate;
          break;
        }
      }
      expect(anchor, isNotNull);
      final anchoredPost = anchor!;
      final topBeforePrepend = tester.getTopLeft(anchoredPost).dy;

      postGate.complete();
      await tester.pumpAndSettle();

      expect(controller.currentPostIds, [
        for (var id = 41; id <= 100; id++) id,
      ]);
      expect(tester.getTopLeft(anchoredPost).dy, closeTo(topBeforePrepend, 1));
    },
  );

  testWidgets('loading earlier posts uses a post skeleton', (tester) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 6; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: '<p>Post $number</p>',
        ),
    };
    final postGate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: posts,
      postGate: postGate,
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
          stream: [for (var id = 1; id <= 6; id++) id],
          postsCount: 6,
        ),
      )
      ..putAll(site.url, [for (var id = 4; id <= 6; id++) posts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 5),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pump();
    await tester.pump();

    expect(api.postFetches, [
      [1, 2, 3],
    ]);
    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.controller!.jumpTo(list.controller!.position.minScrollExtent);
    await tester.pump();
    final skeleton = find.byKey(
      const ValueKey('topic-loading-earlier-skeleton'),
    );
    expect(skeleton, findsOneWidget);
    expect(
      find.descendant(
        of: skeleton,
        matching: find.byType(LoadingSkeletonBlock),
      ),
      findsNWidgets(4),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    postGate.complete();
    await tester.pumpAndSettle();

    expect(skeleton, findsNothing);
    expect(controller.currentPostIds, [1, 2, 3, 4, 5, 6]);
  });

  testWidgets('loading later posts uses a post skeleton', (tester) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 26; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: List.filled(8, '<p>Long post $number</p>').join(),
        ),
    };
    final postGate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: posts,
      postGate: postGate,
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
          stream: [for (var id = 1; id <= 26; id++) id],
          postsCount: 26,
        ),
      )
      ..putAll(site.url, [for (var id = 1; id <= 20; id++) posts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();

    expect(api.postFetches, [
      [for (var id = 21; id <= 26; id++) id],
    ]);
    final skeleton = find.byKey(const ValueKey('topic-loading-more-skeleton'));
    expect(skeleton, findsOneWidget);
    expect(
      find.descendant(
        of: skeleton,
        matching: find.byType(LoadingSkeletonBlock),
      ),
      findsNWidgets(4),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    postGate.complete();
    await tester.pumpAndSettle();

    expect(skeleton, findsNothing);
    expect(controller.currentPostIds, [for (var id = 1; id <= 26; id++) id]);
  });

  testWidgets('a short final page does not move the posts already in view', (
    tester,
  ) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 21; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: '<p>Post $number</p>',
        ),
    };
    final postGate = Completer<void>();
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: posts,
      postGate: postGate,
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
          stream: [for (var id = 1; id <= 21; id++) id],
          postsCount: 21,
        ),
      )
      ..putAll(site.url, [for (var id = 1; id <= 20; id++) posts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();

    expect(api.postFetches, [
      [21],
    ]);
    expect(
      find.byKey(const ValueKey('topic-loading-more-skeleton')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('topic-loading-more-skeleton')))
          .height,
      TopicView.minimumPostHeight,
    );
    final anchor = find.byKey(const ValueKey(20));
    expect(anchor, findsOneWidget);
    final topBeforeAppend = tester.getTopLeft(anchor).dy;

    postGate.complete();
    await tester.pumpAndSettle();

    expect(controller.currentPostIds, [for (var id = 1; id <= 21; id++) id]);
    expect(tester.getTopLeft(anchor).dy, closeTo(topBeforeAppend, 1));
  });

  testWidgets('a pull retries a failed earlier page in a short topic', (
    tester,
  ) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 6; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: '<p>Post $number</p>',
        ),
    };
    final api = _FailingOncePostsApi(posts);
    final controller = _controller(site, api);
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        TopicDetail(
          id: 1,
          title: 'One',
          stream: [for (var id = 1; id <= 6; id++) id],
          postsCount: 6,
        ),
      )
      ..putAll(site.url, [for (var id = 4; id <= 6; id++) posts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 5),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    expect(api.postFetches, [
      [1, 2, 3],
    ]);
    expect(controller.currentPostIds, [4, 5, 6]);

    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.drag(vertical.first, const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(api.postFetches, [
      [1, 2, 3],
      [1, 2, 3],
    ]);
    expect(controller.currentPostIds, [1, 2, 3, 4, 5, 6]);
    expect(controller.currentTopicHasEarlier, isFalse);
  });

  testWidgets('the loaded post window is derived once per change', (
    tester,
  ) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 6; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: '<p>Post $number</p>',
        ),
    };
    final controller = _controller(site, _FailingOncePostsApi(posts));
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        TopicDetail(
          id: 1,
          title: 'One',
          stream: [for (var id = 1; id <= 6; id++) id],
          postsCount: 6,
        ),
      )
      ..putAll(site.url, posts.values);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    // Every shell notification re-selects a snapshot, so the derivation must
    // not walk the store again while nothing it reads has changed.
    final first = controller.currentPostIds;
    expect(first, [1, 2, 3, 4, 5, 6]);
    expect(identical(controller.currentPostIds, first), isTrue);

    // Any post change on the site invalidates the memo.
    controller.store.put(
      site.url,
      const Post(id: 3, postNumber: 3, username: 'sam', cooked: '<p>New</p>'),
    );
    final replaced = controller.currentPostIds;
    expect(identical(replaced, first), isFalse);
    expect(replaced, [1, 2, 3, 4, 5, 6]);
  });

  testWidgets('a scroll retries a failed next page instead of looping', (
    tester,
  ) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 26; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: List.filled(8, '<p>Long post $number</p>').join(),
        ),
    };
    final api = _FailingOncePostsApi(posts);
    final controller = _controller(site, api);
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..put(
        site.url,
        TopicDetail(
          id: 1,
          title: 'One',
          stream: [for (var id = 1; id <= 26; id++) id],
          postsCount: 26,
        ),
      )
      ..putAll(site.url, [for (var id = 1; id <= 20; id++) posts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    expect(api.postFetches, isEmpty);

    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // The failed page rebuilds the last post, and that rebuild must not chain
    // straight into another copy of the same request.
    expect(api.postFetches, [
      [for (var id = 21; id <= 26; id++) id],
    ]);
    expect(controller.currentPostIds, [for (var id = 1; id <= 20; id++) id]);
    expect(controller.currentTopicHasMore, isTrue);

    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.drag(vertical.first, const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(api.postFetches, [
      [for (var id = 21; id <= 26; id++) id],
      [for (var id = 21; id <= 26; id++) id],
    ]);
    expect(controller.currentPostIds, [for (var id = 1; id <= 26; id++) id]);
    expect(controller.currentTopicHasMore, isFalse);
  });

  testWidgets('pulling past the first post does not fetch it again', (
    tester,
  ) async {
    final site = instance('meta.example');
    final posts = {
      for (var number = 1; number <= 6; number++)
        number: Post(
          id: number,
          postNumber: number,
          username: 'sam',
          cooked: '<p>Post $number</p>',
        ),
    };
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: posts,
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
          stream: [for (var id = 1; id <= 6; id++) id],
          postsCount: 6,
        ),
      )
      ..putAll(site.url, posts.values);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();
    expect(controller.currentTopicHasEarlier, isFalse);
    expect(api.postFetches, isEmpty);

    final vertical = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    await tester.drag(vertical.first, const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(api.postFetches, isEmpty);
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

  testWidgets('an earlier-page header can build before scroll layout', (
    tester,
  ) async {
    final site = instance('meta.example');
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      postsById: const {
        1: Post(id: 1, postNumber: 1, username: 'sam', cooked: '<p>One</p>'),
      },
    );
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
    controller.store
      ..put(
        site.url,
        const TopicDetail(
          id: 1,
          title: 'One',
          stream: [1, 2, 3],
          postsCount: 3,
        ),
      )
      ..putAll(site.url, const [
        Post(id: 2, postNumber: 2, username: 'sam', cooked: '<p>Two</p>'),
        Post(id: 3, postNumber: 3, username: 'sam', cooked: '<p>Three</p>'),
      ]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));

    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();

    expect(api.postFetches, const [
      [1],
    ]);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
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

  test('post paging clamps caller batches to one server chunk', () async {
    final site = instance('meta.example');
    final allPosts = {
      for (var number = 1; number <= 60; number++)
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
          stream: [for (var id = 1; id <= 60; id++) id],
          postsCount: 60,
        ),
      )
      ..putAll(site.url, [for (var id = 21; id <= 40; id++) allPosts[id]!]);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One', postNumber: 30),
    );

    await controller.loadMorePosts(batchSize: 1000);
    await controller.loadEarlierPosts(batchSize: 1000);

    expect(api.postFetches, [
      [for (var id = 41; id <= 60; id++) id],
      [for (var id = 1; id <= 20; id++) id],
    ]);
  });

  test(
    'topic progress resolves an unloaded stream id before jumping',
    () async {
      final site = instance('meta.example');
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        postsById: const {
          300: Post(
            id: 300,
            postNumber: 12,
            username: 'sam',
            cooked: '<p>Target</p>',
          ),
        },
      );
      final controller = _controller(site, api);
      addTearDown(controller.dispose);
      await controller.load();
      controller.store
        ..put(
          site.url,
          const TopicDetail(
            id: 1,
            title: 'One',
            stream: [100, 200, 300],
            postsCount: 3,
          ),
        )
        ..put(
          site.url,
          const Post(
            id: 100,
            postNumber: 1,
            username: 'sam',
            cooked: '<p>First</p>',
          ),
        );
      controller.pushContent(
        ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
      );

      expect(await controller.jumpToCurrentTopicIndex(3), isTrue);

      expect(api.postFetches, const [
        [300],
      ]);
      expect(controller.currentContent?.postNumber, 12);
      expect(controller.store.read<Post>(site.url, 300)?.postNumber, 12);
    },
  );

  testWidgets('topic progress opens a stream-position navigator', (
    tester,
  ) async {
    final site = instance('meta.example');
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []});
    final controller = _controller(site, api);
    addTearDown(controller.dispose);
    await controller.load();
    _storeFullTopic(controller, site.url, topicId: 1, firstPostId: 100);
    controller.pushContent(
      ContentRoute.topic(topicId: 1, slug: 'one', title: 'One'),
    );

    await tester.pumpWidget(_topicView(controller));
    await tester.pumpAndSettle();

    final progress = find.byKey(const ValueKey('topic-progress-button'));
    expect(progress, findsOneWidget);
    expect(find.textContaining('/ 30'), findsOneWidget);

    await tester.tap(progress);
    await tester.pumpAndSettle();

    expect(find.text('Topic progress'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-progress-slider')), findsOneWidget);
    expect(find.text('First post'), findsOneWidget);
    expect(find.text('Latest post'), findsOneWidget);

    await tester.tap(find.text('Latest post'));
    await tester.pumpAndSettle();

    expect(controller.currentContent?.postNumber, 30);
    expect(find.byKey(const ValueKey('topic-progress-slider')), findsNothing);
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

final class _FailingOncePostsApi extends FakeDiscourseApi {
  _FailingOncePostsApi(Map<int, Post> posts)
    : super(feeds: const {'/latest.json': []}, postsById: posts);

  var _failed = false;

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    postFetches.add(List.of(ids));
    if (!_failed) {
      _failed = true;
      throw StateError('transient failure');
    }
    return ids.map((id) => postsById[id]).whereType<Post>().toList();
  }

  @override
  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    postFetches.add(List.of(ids));
    if (!_failed) {
      _failed = true;
      throw StateError('transient failure');
    }
    return (
      posts: ids.map((id) => postsById[id]).whereType<Post>().toList(),
      recommendations: null,
    );
  }
}

void _resumeLifecycle(WidgetTester tester) {
  var state = tester.binding.lifecycleState;
  if (state == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    state = AppLifecycleState.hidden;
  }
  if (state == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    state = AppLifecycleState.inactive;
  }
  if (state == AppLifecycleState.inactive) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}
