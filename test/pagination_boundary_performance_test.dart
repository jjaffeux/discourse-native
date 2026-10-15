import 'dart:async';
import 'dart:collection';

import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/utils/pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/mixed_topic_scroll_fixture.dart';
import 'support/topic_list_scroll_fixture.dart';
import 'support/topic_post_list.dart';
import 'support/topic_scroll_fixture.dart';

void main() {
  testWidgets('a fast topic-list fling requests before the reading threshold', (
    tester,
  ) async {
    final controller = (await tester.runAsync(
      () => topicListScrollController(count: 90, pageSize: 30),
    ))!;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller.topicFeeds,
              builder: (_, _) => TopicListView(feed: controller.currentFeed!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(controller.currentFeed!.loadingMore, isFalse);
    await tester.fling(scrollable, const Offset(0, -300), 8000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    debugPrint(
      'PAGINATION_LIST_FLING remaining=${position.extentAfter} '
      'velocity=${position.activity?.velocity}',
    );
    expect(
      position.extentAfter,
      greaterThan(paginationPrefetchDistance(position)),
    );
    expect(controller.currentFeed!.loadingMore, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a fast post fling requests before the reading threshold', (
    tester,
  ) async {
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final api = FakeDiscourseApi(postGate: gate, topics: {}, postsById: {});
    final controller = await mixedTopicScrollController(api: api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(TopicScrollFixture(controller: controller));
    await tester.pumpAndSettle();
    final scroll = topicPostList(tester).controller!;
    // Measure the rich replies around the target before testing a fling;
    // their first HTML layout can increase the estimated remaining extent.
    for (var attempt = 0; attempt < 5; attempt++) {
      scroll.jumpTo(scroll.position.maxScrollExtent - 2400);
      await tester.pumpAndSettle();
      if (scroll.position.extentAfter < 2800) break;
    }
    expect(controller.loadingMorePosts, isFalse);
    await tester.fling(topicPostListFinder(), const Offset(0, -300), 8000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    debugPrint(
      'PAGINATION_POST_FLING remaining=${scroll.position.extentAfter} '
      'velocity=${scroll.position.activity?.velocity}',
    );
    expect(
      scroll.position.extentAfter,
      greaterThan(paginationPrefetchDistance(scroll.position)),
    );
    expect(controller.loadingMorePosts, isTrue);
    gate.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('paging a long topic list indexes retained rows once', (
    tester,
  ) async {
    final controller = await topicListScrollController(count: 1000);
    addTearDown(controller.dispose);
    final ids = _CountingIds(controller.currentFeed!.topicIds);
    final feed = ValueNotifier(controller.currentFeed!.copyWith(topicIds: ids));
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ValueListenableBuilder<TopicFeed>(
              valueListenable: feed,
              builder: (_, value, _) => TopicListView(feed: value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    position.jumpTo(position.maxScrollExtent - 800);
    await tester.pumpAndSettle();
    final offset = position.pixels;

    ids.reads = 0;
    feed.value = feed.value.copyWith(loadingMore: true);
    await tester.pump();
    final loadingReads = ids.reads;
    controller.store.put(
      controller.currentInstance!.url,
      const Topic(id: 1001, title: 'Appended topic', slug: 'appended-topic'),
    );
    final appended = _CountingIds([...ids, 1001]);
    feed.value = feed.value.copyWith(topicIds: appended, loadingMore: false);
    await tester.pumpAndSettle();
    debugPrint(
      'PAGINATION_LIST_READS loading=$loadingReads append=${appended.reads}',
    );
    expect(loadingReads, lessThan(500));
    expect(appended.reads, lessThan(appended.length + 500));
    expect(position.pixels, closeTo(offset, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final tail in [20, 21, 100, 9000]) {
    test(
      'planning 20 posts does bounded work with $tail posts remaining',
      () async {
        final site = instance('paging.example');
        final gate = Completer<void>();
        const recommendations = TopicRecommendations(sources: []);
        final api = FakeDiscourseApi(
          postGate: gate,
          postsById: {
            for (var id = 21; id <= 40; id++)
              id: Post(
                id: id,
                postNumber: id,
                username: 'sam',
                cooked: '<p>$id</p>',
              ),
          },
          postRecommendations: {7: recommendations},
        );
        final store = _CountingStore();
        final controller = ShellController(
          instanceStore: FakeInstanceStore([site]),
          api: api,
          store: store,
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          updateStore: FakeUpdateStore(),
        );
        addTearDown(controller.dispose);
        await controller.load();
        store
          ..put(
            site.url,
            TopicDetail(
              id: 7,
              title: 'Long topic',
              stream: [for (var id = 1; id <= tail + 20; id++) id],
              postsCount: tail + 20,
            ),
          )
          ..putAll(site.url, [
            for (var id = 1; id <= 20; id++)
              Post(
                id: id,
                postNumber: id,
                username: 'sam',
                cooked: '<p>$id</p>',
              ),
          ]);
        controller.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'long-topic',
            title: 'Long topic',
          ),
        );
        // Warm the same window read by the viewport before a scroll starts paging.
        expect(controller.currentPostIds, hasLength(20));
        store.postLookups = 0;
        final loading = controller.loadMorePosts();
        await pumpEventQueue();
        final lookups = store.postLookups;
        debugPrint('PAGINATION_POST_LOOKUPS tail=$tail lookups=$lookups');
        expect(api.postFetches.single, [for (var id = 21; id <= 40; id++) id]);
        gate.complete();
        await loading;
        expect(lookups, lessThan(100));
        expect(controller.currentPostIds, hasLength(40));
        expect(controller.currentTopicHasMore, tail > 20);
        expect(
          controller.currentTopic!.recommendations,
          tail == 20 ? same(recommendations) : isNull,
          reason: 'Recommendations are resolved only with the final page',
        );
      },
    );
  }
}

class _CountingIds extends ListBase<int> {
  _CountingIds(this.values);
  final List<int> values;
  int reads = 0;

  @override
  int get length => values.length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  int operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('immutable');
}

class _CountingStore extends Store {
  int postLookups = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) postLookups++;
    return super.read<T>(siteUrl, id);
  }

  @override
  bool containsRecord<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) postLookups++;
    return super.containsRecord<T>(siteUrl, id);
  }
}
