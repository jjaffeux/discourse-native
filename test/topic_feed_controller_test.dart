import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/incoming_topics.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

final class _PendingFeed {
  _PendingFeed({required this.siteUrl, required this.path});

  final String siteUrl;
  final String path;
  final Completer<TopicList> response = Completer();
}

final class _ControlledTopicFeedsApi extends FakeDiscourseApi {
  final List<_PendingFeed> requests = [];

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    final list = await topicList(siteUrl: siteUrl, path: '/t/$id.json');
    return list.topics.firstWhere((topic) => topic.id == id);
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final request = _PendingFeed(siteUrl: siteUrl, path: path);
    requests.add(request);
    return request.response.future;
  }
}

final class _GatedCredentialReader implements SiteApiKeyReader {
  final Completer<void> started = Completer();
  final Completer<String?> result = Completer();

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    started.complete();
    return result.future;
  }
}

final class _FirstGatedCredentialReader implements SiteApiKeyReader {
  final Completer<void> started = Completer<void>();
  final Completer<String?> result = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    if (started.isCompleted) return Future.value('new-key');
    started.complete();
    return result.future;
  }
}

TopicList _page(int id, {String? moreTopicsUrl}) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
  moreTopicsUrl: moreTopicsUrl,
);

TopicList _pages(Iterable<int> ids, {String? moreTopicsUrl}) => TopicList(
  topics: [
    for (final id in ids) Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
  ],
  moreTopicsUrl: moreTopicsUrl,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControlledTopicFeedsApi api;
  late FakeApiCredentialReader credentials;
  late Store store;
  late TopicFeedController controller;

  setUp(() {
    api = _ControlledTopicFeedsApi();
    credentials = FakeApiCredentialReader();
    store = Store();
    controller = TopicFeedController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      store: store,
    );
  });

  tearDown(() {
    controller.dispose();
    for (final request in api.requests) {
      if (!request.response.isCompleted) {
        request.response.complete(const TopicList(topics: []));
      }
    }
  });

  group('bounded cache reuse', () {
    final site = instance('one.example');

    setUp(() {
      controller.dispose();
      store = Store(maxEntries: 2);
      controller = TopicFeedController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        store: store,
      );
    });

    Future<void> loadFeed(String destination, List<int> ids) async {
      final loading = controller.load(
        instance: site,
        destinationId: destination,
        path: '/$destination.json',
        incoming: null,
      );
      await pumpEventQueue();
      api.requests.last.response.complete(_pages(ids));
      await loading;
    }

    for (final ids in [
      <int>[],
      [1, 2],
    ]) {
      test('reuses a backed feed containing $ids', () async {
        await loadFeed('latest', ids);
        final cached = controller.feedFor(site.url, 'latest');
        controller.saveScrollRow(site.url, 'latest', 1);

        await controller.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );

        expect(api.requests, hasLength(1));
        expect(controller.feedFor(site.url, 'latest'), same(cached));
        expect(controller.scrollRowFor(site.url, 'latest'), 1);
        expect(store.length, ids.length);
      });
    }

    for (final otherIds in [
      <int>[3, 4],
      [1, 3],
    ]) {
      test('refills evicted topics after loading $otherIds', () async {
        await loadFeed('latest', [1, 2]);
        await loadFeed('hot', otherIds);
        expect(controller.feedFor(site.url, 'latest')?.topicIds, [1, 2]);
        expect(store.containsRecord<Topic>(site.url, 2), isFalse);
        expect(store.containsRecord<Topic>(site.url, 1), otherIds.contains(1));
        expect(store.length, 2);
        controller.saveScrollRow(site.url, 'latest', 1);

        final refill = controller.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );
        final duplicate = controller.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );
        await pumpEventQueue();

        expect(api.requests, hasLength(3));
        expect(api.requests.last.path, '/latest.json');
        expect(duplicate, same(refill));
        expect(controller.feedFor(site.url, 'latest')?.loading, isTrue);

        api.requests.last.response.complete(_pages([1, 2]));
        await Future.wait([refill, duplicate]);

        final recovered = controller.feedFor(site.url, 'latest')!;
        expect(recovered.topicIds, [1, 2]);
        expect(recovered.loaded, isTrue);
        expect(recovered.loading, isFalse);
        expect(recovered.error, isNull);
        expect(store.read<Topic>(site.url, 1)?.title, 'Topic 1');
        expect(store.read<Topic>(site.url, 2)?.title, 'Topic 2');
        expect(controller.scrollRowFor(site.url, 'latest'), 0);
        expect(store.length, 2);
        expect(store.statisticsForTesting.observedEntries, 0);
      });
    }

    test(
      'retries a failed refill and restores incoming announcements',
      () async {
        await loadFeed('latest', [1, 2]);
        await loadFeed('hot', [3, 4]);
        final incoming = IncomingTopics()
          ..notify({'message_type': 'new_topic', 'topic_id': 5});

        Future<void> revisit() => controller.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: incoming,
        );

        final refill = revisit();
        await pumpEventQueue();
        expect(api.requests, hasLength(3));
        expect(incoming.count('latest'), 0);
        api.requests.last.response.completeError(
          SiteLookupException(SiteLookupFailure.unreachable, site.url),
        );
        await refill;

        final failed = controller.feedFor(site.url, 'latest')!;
        expect(failed.loading, isFalse);
        expect(failed.error, "Couldn't reach one.example.");
        expect(failed.pageError, isFalse);
        expect(incoming.count('latest'), 1);

        final retry = revisit();
        final duplicate = revisit();
        expect(duplicate, same(retry));
        await pumpEventQueue();
        expect(api.requests, hasLength(4));
        expect(controller.feedFor(site.url, 'latest')?.error, isNull);
        api.requests.last.response.complete(_pages([5, 1]));
        await Future.wait([retry, duplicate]);

        expect(controller.feedFor(site.url, 'latest')?.topicIds, [5, 1]);
        expect(controller.feedFor(site.url, 'latest')?.error, isNull);
        expect(store.read<Topic>(site.url, 5)?.title, 'Topic 5');
        expect(store.read<Topic>(site.url, 1)?.title, 'Topic 1');
        expect(incoming.count('latest'), 0);
        expect(store.length, 2);
      },
    );

    test('checking a backed feed leaves eviction order unchanged', () async {
      await loadFeed('latest', [1, 2]);
      store.read<Topic>(site.url, 1);

      await controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await loadFeed('hot', [3]);

      expect(api.requests, hasLength(2));
      expect(store.containsRecord<Topic>(site.url, 1), isTrue);
      expect(store.containsRecord<Topic>(site.url, 2), isFalse);
      expect(store.containsRecord<Topic>(site.url, 3), isTrue);
      expect(store.length, 2);
    });
  });

  group('initial loading and refresh', () {
    test('coalesces one retry after an initial failure', () async {
      final site = instance('one.example');
      final failed = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await pumpEventQueue();

      api.requests.single.response.completeError(
        SiteLookupException(SiteLookupFailure.unreachable, site.url),
      );
      await failed;

      final failure = controller.feedFor(site.url, 'latest')!;
      expect(failure.topicIds, isEmpty);
      expect(failure.loading, isFalse);
      expect(failure.error, "Couldn't reach one.example.");

      final retry = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      final duplicate = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      expect(duplicate, same(retry));
      await pumpEventQueue();

      expect(api.requests, hasLength(2));
      api.requests.last.response.complete(_page(1));
      await Future.wait([retry, duplicate]);

      expect(controller.feedFor(site.url, 'latest')?.topicIds, [1]);
      expect(controller.feedFor(site.url, 'latest')?.error, isNull);
    });

    test(
      'preserves stale rows and scroll state through a refresh failure',
      () async {
        final site = instance('one.example');
        final initial = controller.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );
        await pumpEventQueue();
        api.requests.single.response.complete(
          _page(1, moreTopicsUrl: '/latest?page=1'),
        );
        await initial;
        controller.saveScrollRow(site.url, 'latest', 11);

        final refresh = controller.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
          force: true,
        );
        await pumpEventQueue();

        final refreshing = controller.feedFor(site.url, 'latest')!;
        expect(refreshing.topicIds, [1]);
        expect(refreshing.loading, isTrue);
        expect(refreshing.loaded, isTrue);
        expect(refreshing.hasMore, isTrue);
        expect(controller.scrollRowFor(site.url, 'latest'), 11);

        api.requests.last.response.completeError(
          SiteLookupException(SiteLookupFailure.unreachable, site.url),
        );
        await refresh;

        final stale = controller.feedFor(site.url, 'latest')!;
        expect(stale.topicIds, [1]);
        expect(stale.loading, isFalse);
        expect(stale.error, "Couldn't reach one.example.");
        expect(stale.pageError, isFalse);
        expect(stale.hasMore, isTrue);
        expect(controller.scrollRowFor(site.url, 'latest'), 11);
      },
    );
  });

  group('pagination', () {
    test(
      'bounds retained identities past the production Store budget',
      () async {
        final site = instance('one.example');
        controller.dispose();
        store = Store(
          policy: const StorePolicy(
            maxEntries: 4096,
            maxEntriesPerSite: 2048,
            maxEntriesPerSiteAndType: 1024,
          ),
        );
        controller = TopicFeedController(
          api: api,
          credentials: credentials,
          lifecycle: SiteLifecycle(),
          store: store,
        );
        for (var page = 0; page < 35; page++) {
          final loading = page == 0
              ? controller.load(
                  instance: site,
                  destinationId: 'latest',
                  path: '/latest.json',
                  incoming: null,
                )
              : controller.loadMore(instance: site, destinationId: 'latest');
          await pumpEventQueue();
          api.requests.last.response.complete(
            TopicList(
              topics: [
                for (var row = 0; row < 30; row++)
                  Topic(
                    id: page * 30 + row + 1,
                    title: 'Topic ${page * 30 + row + 1}',
                    slug: 'topic',
                  ),
              ],
              moreTopicsUrl: '/latest.json?page=${page + 1}',
            ),
          );
          await loading;
        }
        final feed = controller.feedFor(site.url, 'latest')!;
        expect(api.requests, hasLength(35));
        expect(feed.topicIds.length, lessThanOrEqualTo(300));
        expect(
          feed.topicIds.every(
            (id) => store.containsRecord<Topic>(site.url, id),
          ),
          isTrue,
        );
        expect(store.statisticsForTesting.entriesFor<Topic>(site.url), 1024);

        final restoring = controller.ensureRange(
          instance: site,
          destinationId: 'latest',
          firstRow: 300,
          lastRow: 329,
        );
        await pumpEventQueue();
        expect(api.requests.last.path, '/latest.json?page=10');
        api.requests.last.response.complete(
          _pages(
            List.generate(30, (index) => index + 301),
            moreTopicsUrl: '/latest.json?page=11',
          ),
        );
        await restoring;
        final restored = controller.feedFor(site.url, 'latest')!;
        expect(restored.rowCount, 1050);
        expect(restored.topicIdAt(300), 301);
        expect(restored.topicIdAt(329), 330);
        expect(restored.nextPagePath, '/latest.json?page=35');
        expect(restored.topicIds.length, lessThanOrEqualTo(300));
        expect(store.read<Topic>(site.url, 301)?.title, 'Topic 301');
        expect(store.statisticsForTesting.observedEntries, 0);
      },
    );

    test('keeps the cursor and coalesces retry after a page failure', () async {
      final site = instance('one.example');
      final initial = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await pumpEventQueue();
      api.requests.single.response.complete(
        _page(1, moreTopicsUrl: '/latest?page=1'),
      );
      await initial;

      final failedPage = controller.loadMore(
        instance: site,
        destinationId: 'latest',
      );
      final duplicatePage = controller.loadMore(
        instance: site,
        destinationId: 'latest',
      );
      await pumpEventQueue();
      expect(api.requests, hasLength(2));

      api.requests.last.response.completeError(Exception('offline'));
      await Future.wait([failedPage, duplicatePage]);

      final failed = controller.feedFor(site.url, 'latest')!;
      expect(failed.topicIds, [1]);
      expect(failed.loadingMore, isFalse);
      expect(failed.pageError, isTrue);
      expect(failed.hasMore, isTrue);
      expect(failed.error, "Couldn't load more topics from one.example.");

      final retry = controller.loadMore(
        instance: site,
        destinationId: 'latest',
      );
      final duplicateRetry = controller.loadMore(
        instance: site,
        destinationId: 'latest',
      );
      await pumpEventQueue();
      expect(api.requests, hasLength(3));

      api.requests.last.response.complete(_page(2));
      await Future.wait([retry, duplicateRetry]);

      final recovered = controller.feedFor(site.url, 'latest')!;
      expect(recovered.topicIds, [1, 2]);
      expect(recovered.error, isNull);
      expect(recovered.pageError, isFalse);
      expect(recovered.hasMore, isFalse);
    });

    test('advances the cursor for a page of already-known topics', () async {
      final site = instance('one.example');
      final initial = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await pumpEventQueue();
      api.requests.single.response.complete(
        _page(1, moreTopicsUrl: '/latest?page=1'),
      );
      await initial;

      final familiarPage = controller.loadMore(
        instance: site,
        destinationId: 'latest',
      );
      await pumpEventQueue();
      expect(api.requests, hasLength(2));
      api.requests.last.response.complete(
        _page(1, moreTopicsUrl: '/latest?page=2'),
      );
      await familiarPage;

      final advanced = controller.feedFor(site.url, 'latest')!;
      expect(advanced.topicIds, [1]);
      expect(advanced.hasMore, isTrue);

      final nextPage = controller.loadMore(
        instance: site,
        destinationId: 'latest',
      );
      await pumpEventQueue();
      expect(api.requests, hasLength(3));
      expect(api.requests.last.path, '/latest.json?page=2');
      api.requests.last.response.complete(_page(2));
      await nextPage;

      final done = controller.feedFor(site.url, 'latest')!;
      expect(done.topicIds, [1, 2]);
      expect(done.hasMore, isFalse);
    });

    test('ends when a page repeats its own cursor', () async {
      final site = instance('one.example');
      final initial = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await pumpEventQueue();
      api.requests.single.response.complete(
        _page(1, moreTopicsUrl: '/latest?page=1'),
      );
      await initial;

      final stuckPage = controller.loadMore(
        instance: site,
        destinationId: 'latest',
      );
      await pumpEventQueue();
      api.requests.last.response.complete(
        _page(2, moreTopicsUrl: '/latest?page=1'),
      );
      await stuckPage;

      final stalled = controller.feedFor(site.url, 'latest')!;
      expect(stalled.topicIds, [1, 2]);
      expect(stalled.hasMore, isFalse);

      await controller.loadMore(instance: site, destinationId: 'latest');
      expect(api.requests, hasLength(2));
    });
  });

  group('range restoration', () {
    final site = instance('one.example');
    const rootPath = '/filter.json?tags=one&order=created';

    setUp(() {
      controller.dispose();
      controller = TopicFeedController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        store: store,
        maximumRetainedTopics: 4,
        maximumCursorCheckpoints: 2,
        maximumDestinations: 2,
      );
    });

    Future<void> seed({int pages = 6}) async {
      for (var page = 0; page < pages; page++) {
        final loading = page == 0
            ? controller.load(
                instance: site,
                destinationId: 'filtered',
                path: rootPath,
                incoming: null,
              )
            : controller.loadMore(instance: site, destinationId: 'filtered');
        await pumpEventQueue();
        api.requests.last.response.complete(
          _pages([
            page * 2 + 1,
            page * 2 + 2,
          ], moreTopicsUrl: '/cursor/${page + 1}.json?token=opaque'),
        );
        await loading;
      }
    }

    Future<void> restore(int first, int last) => controller.ensureRange(
      instance: site,
      destinationId: 'filtered',
      firstRow: first,
      lastRow: last,
    );

    Future<void> answer(List<int> ids, {String? next}) async {
      await pumpEventQueue();
      api.requests.last.response.complete(_pages(ids, moreTopicsUrl: next));
      await pumpEventQueue();
    }

    test(
      'replays dropped opaque checkpoints without changing the frontier',
      () async {
        await seed();
        expect(controller.feedFor(site.url, 'filtered')?.topicIdAt(2), isNull);
        final restoring = restore(2, 3);
        final duplicate = restore(2, 3);
        expect(duplicate, same(restoring));
        await pumpEventQueue();
        expect(api.requests.last.path, rootPath);
        await answer([1, 2], next: '/cursor/1.json?token=opaque');
        expect(api.requests.last.path, '/cursor/1.json?token=opaque');
        await answer([3, 4], next: '/cursor/2.json?token=opaque');
        await restoring;

        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIdAt(2), 3);
        expect(feed.topicIdAt(3), 4);
        expect(feed.rowCount, 12);
        expect(feed.nextPagePath, '/cursor/6.json?token=opaque');
        expect(feed.topicIds.length, lessThanOrEqualTo(4));
        expect(feed.error, isNull);
        final requestsBefore = api.requests.length;
        await restore(2, 3);
        expect(api.requests, hasLength(requestsBefore));

        final forward = controller.loadMore(
          instance: site,
          destinationId: 'filtered',
        );
        await pumpEventQueue();
        expect(api.requests.last.path, '/cursor/6.json?token=opaque');
        await answer([13, 14], next: '/cursor/7.json?token=opaque');
        await forward;
        expect(controller.feedFor(site.url, 'filtered')?.rowCount, 14);
      },
    );

    for (final pageFirst in [false, true]) {
      test(
        'serializes restoration and pagination with page first=$pageFirst',
        () async {
          await seed();
          late Future<void> restoring;
          late Future<void> forward;
          if (pageFirst) {
            forward = controller.loadMore(
              instance: site,
              destinationId: 'filtered',
            );
            await pumpEventQueue();
            restoring = restore(2, 3);
            await pumpEventQueue();
            expect(api.requests, hasLength(7));
            expect(api.requests.last.path, '/cursor/6.json?token=opaque');
            await answer([13, 14], next: '/cursor/7.json?token=opaque');
            await forward;
          } else {
            restoring = restore(2, 3);
            await pumpEventQueue();
            forward = controller.loadMore(
              instance: site,
              destinationId: 'filtered',
            );
            await pumpEventQueue();
            expect(api.requests, hasLength(7));
          }
          expect(api.requests.last.path, rootPath);
          await answer([1, 2], next: '/cursor/1.json?token=opaque');
          await answer([3, 4], next: '/cursor/2.json?token=opaque');
          await restoring;
          if (!pageFirst) {
            expect(api.requests.last.path, '/cursor/6.json?token=opaque');
            await answer([13, 14], next: '/cursor/7.json?token=opaque');
            await forward;
          }
          final feed = controller.feedFor(site.url, 'filtered')!;
          expect(feed.rowCount, 14);
          expect(feed.nextPagePath, '/cursor/7.json?token=opaque');
        },
      );
    }

    test('coalesces overlapping ranges while a replay is in flight', () async {
      await seed();
      final first = restore(2, 3);
      await pumpEventQueue();
      final second = restore(2, 5);
      expect(second, same(first));
      await answer([1, 2], next: '/cursor/1.json?token=opaque');
      await answer([3, 4], next: '/cursor/2.json?token=opaque');
      expect(api.requests.last.path, '/cursor/2.json?token=opaque');
      await answer([5, 6], next: '/cursor/3.json?token=opaque');
      await Future.wait([first, second]);
      final feed = controller.feedFor(site.url, 'filtered')!;
      expect(
        [for (var row = 2; row <= 5; row++) feed.topicIdAt(row)],
        [3, 4, 5, 6],
      );
      expect(feed.topicIds, hasLength(4));
    });

    test(
      'repairs retained rows evicted by another feed using stable topic IDs',
      () async {
        await seed(pages: 2);
        store.forget(site.url);
        final restoring = restore(1, 2);
        await pumpEventQueue();
        expect(api.requests.last.path, '/t/2.json');
        await answer([2]);
        expect(api.requests.last.path, '/t/3.json');
        await answer([3]);
        await restoring;
        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIds, [1, 2, 3, 4]);
        expect(feed.rowCount, 4);
        expect(feed.nextPagePath, '/cursor/2.json?token=opaque');
        expect(store.read<Topic>(site.url, 2)?.title, 'Topic 2');
        expect(store.read<Topic>(site.url, 3)?.title, 'Topic 3');
      },
    );

    test(
      'keeps visible ranges for two panels while pruning old rows',
      () async {
        final firstOwner = Object();
        final secondOwner = Object();
        final firstRelease = controller.retainFeed(
          site.url,
          'filtered',
          owner: firstOwner,
        );
        final secondRelease = controller.retainFeed(
          site.url,
          'filtered',
          owner: secondOwner,
        );
        controller.updateViewport(
          site.url,
          'filtered',
          owner: firstOwner,
          firstRow: 0,
          lastRow: 1,
        );
        controller.updateViewport(
          site.url,
          'filtered',
          owner: secondOwner,
          firstRow: 8,
          lastRow: 9,
        );
        await seed();
        var feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIds, [1, 2, 9, 10]);
        expect(feed.rowCount, 12);
        final beforeViewportUpdate = feed;
        controller.updateViewport(
          site.url,
          'filtered',
          owner: secondOwner,
          firstRow: 8,
          lastRow: 9,
        );
        expect(
          controller.feedFor(site.url, 'filtered'),
          same(beforeViewportUpdate),
        );
        firstRelease();
        firstRelease();
        final forward = controller.loadMore(
          instance: site,
          destinationId: 'filtered',
        );
        await answer([13, 14], next: '/cursor/7.json?token=opaque');
        await forward;
        feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIds, [9, 10, 13, 14]);
        secondRelease();
      },
    );

    for (final includesVisible in [false, true]) {
      test(
        'shifts protected panels before trimming an incoming prepend, overlap=$includesVisible',
        () async {
          final firstOwner = Object();
          final secondOwner = Object();
          final firstRelease = controller.retainFeed(
            site.url,
            'filtered',
            owner: firstOwner,
          );
          final secondRelease = controller.retainFeed(
            site.url,
            'filtered',
            owner: secondOwner,
          );
          controller.updateViewport(
            site.url,
            'filtered',
            owner: firstOwner,
            firstRow: 0,
            lastRow: 1,
          );
          controller.updateViewport(
            site.url,
            'filtered',
            owner: secondOwner,
            firstRow: 8,
            lastRow: 9,
          );
          await seed();
          final incoming = IncomingTopics()
            ..track({'filtered': const IncomingTopicsFilter.latest()})
            ..notify({'message_type': 'new_topic', 'topic_id': 100});
          if (includesVisible) {
            incoming.notify({'message_type': 'new_topic', 'topic_id': 10});
          }
          final showing = controller.showIncoming(
            instance: site,
            destinationId: 'filtered',
            path: rootPath,
            incoming: incoming,
          );
          await answer([100, if (includesVisible) 10]);
          await showing;
          final feed = controller.feedFor(site.url, 'filtered')!;
          final delta = includesVisible ? 2 : 1;
          expect(feed.topicIdAt(delta), 1);
          expect(feed.topicIdAt(delta + 1), 2);
          expect(feed.topicIdAt(8 + delta), 9);
          expect(feed.topicIdAt(includesVisible ? 1 : 10), 10);
          expect(feed.rowCount, 13);
          expect(feed.topicIds.length, lessThanOrEqualTo(4));
          firstRelease();
          secondRelease();
        },
      );
    }

    test(
      'keeps range errors retryable without collapsing rows or losing cursors',
      () async {
        await seed();
        final failed = restore(2, 3);
        await pumpEventQueue();
        api.requests.last.response.completeError(StateError('offline'));
        await failed;
        var feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.pageError, isTrue);
        expect(feed.rowCount, 12);
        expect(feed.topicIdAt(2), isNull);
        expect(feed.nextPagePath, '/cursor/6.json?token=opaque');
        final retry = restore(2, 3);
        final duplicate = restore(2, 3);
        expect(duplicate, same(retry));
        await answer([1, 2], next: '/cursor/1.json?token=opaque');
        await answer([3, 4], next: '/cursor/2.json?token=opaque');
        await retry;
        feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIdAt(2), 3);
        expect(feed.error, isNull);
        expect(feed.rowCount, 12);
      },
    );

    test(
      'stops a repeated replay cursor and retains a retryable sparse range',
      () async {
        await seed();
        final restoring = restore(2, 3);
        await answer([1, 2], next: rootPath);
        await restoring;
        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(api.requests, hasLength(7));
        expect(feed.pageError, isTrue);
        expect(feed.rowCount, 12);
        expect(feed.topicIdAt(2), isNull);
        expect(feed.nextPagePath, '/cursor/6.json?token=opaque');
      },
    );

    test(
      'reconciles stale tail rows when a changed server list ends early',
      () async {
        await seed();
        final restoring = restore(2, 3);
        await answer([101]);
        await restoring;
        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(api.requests, hasLength(7));
        expect(feed.pageError, isFalse);
        expect(feed.rowCount, 1);
        expect(feed.topicIdAt(0), 101);
        expect(feed.topicIdAt(2), isNull);
        expect(feed.nextPagePath, isNull);
      },
    );

    test(
      'refresh cancels an old replay and resets its sparse metadata',
      () async {
        await seed();
        final restoring = restore(2, 3);
        await pumpEventQueue();
        final oldRequest = api.requests.last;
        final refresh = controller.load(
          instance: site,
          destinationId: 'filtered',
          path: '/new.json',
          incoming: null,
          force: true,
        );
        await pumpEventQueue();
        expect(api.requests.last.path, '/new.json');
        await answer([100], next: '/new.json?page=1');
        await refresh;
        oldRequest.response.complete(
          _pages([1, 2], moreTopicsUrl: '/cursor/1.json?token=opaque'),
        );
        await restoring;
        await pumpEventQueue();
        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIds, [100]);
        expect(feed.rowCount, 1);
        expect(feed.nextPagePath, '/new.json?page=1');
        expect(feed.error, isNull);
      },
    );

    test(
      'an old account replay cannot write into a replacement feed',
      () async {
        await seed();
        final restoring = restore(2, 3);
        await pumpEventQueue();
        final oldRequest = api.requests.last;
        controller.forget(site.url);
        store.forget(site.url);
        final replacement = controller.load(
          instance: site,
          destinationId: 'filtered',
          path: '/account.json',
          incoming: null,
        );
        await answer([100]);
        await replacement;
        oldRequest.response.complete(
          _pages([1, 2], moreTopicsUrl: '/cursor/1.json?token=opaque'),
        );
        await restoring;
        await pumpEventQueue();
        expect(controller.feedFor(site.url, 'filtered')?.topicIds, [100]);
        expect(store.read<Topic>(site.url, 1), isNull);
        expect(api.requests.last.path, '/account.json');
      },
    );

    test(
      'restores the original row after an overlapping page is evicted',
      () async {
        controller.dispose();
        controller = TopicFeedController(
          api: api,
          credentials: credentials,
          lifecycle: SiteLifecycle(),
          store: store,
          maximumRetainedTopics: 2,
        );
        await seed(pages: 1);
        var forward = controller.loadMore(
          instance: site,
          destinationId: 'filtered',
        );
        await answer([2, 3], next: '/cursor/2.json?token=opaque');
        await forward;
        forward = controller.loadMore(
          instance: site,
          destinationId: 'filtered',
        );
        await answer([4, 5], next: '/cursor/3.json?token=opaque');
        await forward;
        expect(controller.feedFor(site.url, 'filtered')?.rowCount, 5);
        final restoring = restore(2, 2);
        await pumpEventQueue();
        expect(api.requests.last.path, '/cursor/1.json?token=opaque');
        await answer([2, 3], next: '/cursor/2.json?token=opaque');
        await restoring;
        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIdAt(2), 3);
        expect(feed.rowCount, 5);
        expect(feed.error, isNull);
      },
    );

    test(
      'rejects changed checkpoint contents without relocating protected rows',
      () async {
        final owner = Object();
        final release = controller.retainFeed(
          site.url,
          'filtered',
          owner: owner,
        );
        controller.updateViewport(
          site.url,
          'filtered',
          owner: owner,
          firstRow: 8,
          lastRow: 9,
        );
        await seed();
        final restoring = restore(0, 1);
        await answer([9, 10], next: '/cursor/1.json?token=opaque');
        await restoring;
        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIdAt(8), 9);
        expect(feed.topicIdAt(9), 10);
        expect(feed.topicIdAt(0), isNull);
        expect(feed.topicIdAt(1), isNull);
        expect(feed.pageError, isTrue);
        expect(feed.rowCount, 12);
        release();
      },
    );

    for (final checkpoints in [2, 32]) {
      test(
        'reconciles an incoming duplicate with $checkpoints checkpoints',
        () async {
          controller.dispose();
          controller = TopicFeedController(
            api: api,
            credentials: credentials,
            lifecycle: SiteLifecycle(),
            store: store,
            maximumRetainedTopics: 2,
            maximumCursorCheckpoints: checkpoints,
          );
          await seed(pages: 2);
          final incoming = IncomingTopics()
            ..track({'filtered': const IncomingTopicsFilter.latest()})
            ..notify({'message_type': 'new_topic', 'topic_id': 1});
          final showing = controller.showIncoming(
            instance: site,
            destinationId: 'filtered',
            path: rootPath,
            incoming: incoming,
          );
          await answer([1]);
          await showing;
          expect(controller.feedFor(site.url, 'filtered')?.rowCount, 5);
          final owner = Object();
          final release = controller.retainFeed(
            site.url,
            'filtered',
            owner: owner,
          );
          controller.updateViewport(
            site.url,
            'filtered',
            owner: owner,
            firstRow: 0,
            lastRow: 0,
          );
          final first = restore(1, 1);
          await pumpEventQueue();
          if (checkpoints == 2) {
            expect(api.requests.last.path, '$rootPath&topic_ids=1');
            await answer([1]);
          }
          expect(api.requests.last.path, rootPath);
          await answer([1, 2], next: '/cursor/1.json?token=opaque');
          await first;
          final restoring = restore(2, 2);
          await pumpEventQueue();
          expect(api.requests.last.path, '/cursor/1.json?token=opaque');
          await answer([3, 4]);
          await restoring;
          final feed = controller.feedFor(site.url, 'filtered')!;
          expect(feed.rowCount, 4);
          expect(feed.nextPagePath, isNull);
          expect(feed.topicIdAt(4), isNull);
          expect(feed.topicIdAt(0), 1);
          expect(feed.error, isNull);
          release();
        },
      );
    }

    test(
      'replays a retained incoming query after its IDs are evicted',
      () async {
        controller.dispose();
        controller = TopicFeedController(
          api: api,
          credentials: credentials,
          lifecycle: SiteLifecycle(),
          store: store,
          maximumRetainedTopics: 2,
          maximumCursorCheckpoints: 8,
        );
        await seed(pages: 1);
        final incoming = IncomingTopics()
          ..track({'filtered': const IncomingTopicsFilter.latest()})
          ..notify({'message_type': 'new_topic', 'topic_id': 100});
        final showing = controller.showIncoming(
          instance: site,
          destinationId: 'filtered',
          path: rootPath,
          incoming: incoming,
        );
        await answer([100]);
        await showing;
        final forward = controller.loadMore(
          instance: site,
          destinationId: 'filtered',
        );
        await answer([3, 4], next: '/cursor/2.json?token=opaque');
        await forward;
        expect(controller.feedFor(site.url, 'filtered')?.topicIdAt(0), isNull);
        final restoring = restore(0, 1);
        await pumpEventQueue();
        expect(api.requests.last.path, '$rootPath&topic_ids=100');
        await answer([100], next: '/unrelated-filter-page.json');
        expect(api.requests.last.path, rootPath);
        await answer([1, 2], next: '/cursor/1.json?token=opaque');
        await restoring;
        final feed = controller.feedFor(site.url, 'filtered')!;
        expect(feed.topicIdAt(0), 100);
        expect(feed.topicIdAt(1), 1);
        expect(feed.rowCount, 5);
        expect(feed.nextPagePath, '/cursor/2.json?token=opaque');
      },
    );

    test(
      'restores a selected ID without changing sparse row positions',
      () async {
        await seed();
        store.forget(site.url);
        final before = controller.feedFor(site.url, 'filtered')!;
        final restoring = controller.restoreTopic(
          instance: site,
          destinationId: 'filtered',
          topicId: 3,
        );
        final duplicate = controller.restoreTopic(
          instance: site,
          destinationId: 'filtered',
          topicId: 3,
        );
        expect(duplicate, same(restoring));
        await pumpEventQueue();
        expect(api.requests.last.path, '/t/3.json');
        await answer([3, 999]);
        expect((await restoring)?.id, 3);
        expect(store.read<Topic>(site.url, 3)?.title, 'Topic 3');
        expect(store.containsRecord<Topic>(site.url, 999), isFalse);
        expect(controller.feedFor(site.url, 'filtered'), same(before));
      },
    );

    test(
      'rejects a selection response after the account lease changes',
      () async {
        await seed();
        final restoring = controller.restoreTopic(
          instance: site,
          destinationId: 'filtered',
          topicId: 99,
        );
        await pumpEventQueue();
        controller.lifecycle.invalidate(site.url);
        await answer([99]);
        expect(await restoring, isNull);
        expect(store.containsRecord<Topic>(site.url, 99), isFalse);
      },
    );

    test('destination LRU keeps two leases until both are released', () async {
      final releaseFirst = controller.retainFeed(site.url, 'filtered');
      final releaseSecond = controller.retainFeed(site.url, 'filtered');
      await seed(pages: 1);
      controller.saveScrollRow(site.url, 'filtered', 1);
      releaseFirst();
      releaseFirst();
      for (final destination in ['one', 'two']) {
        final loading = controller.load(
          instance: site,
          destinationId: destination,
          path: '/$destination.json',
          incoming: null,
        );
        await answer([20]);
        await loading;
      }
      expect(controller.feedFor(site.url, 'one'), isNull);
      expect(controller.feedFor(site.url, 'filtered'), isNotNull);
      expect(controller.scrollRowFor(site.url, 'filtered'), 1);
      releaseSecond();
      controller.feedFor(site.url, 'two');
      final third = controller.load(
        instance: site,
        destinationId: 'three',
        path: '/three.json',
        incoming: null,
      );
      await answer([30]);
      await third;
      expect(controller.feedFor(site.url, 'filtered'), isNull);
      expect(controller.scrollRowFor(site.url, 'filtered'), 0);
      expect(controller.feedFor(site.url, 'two'), isNotNull);
      expect(controller.feedFor(site.url, 'three'), isNotNull);
    });

    for (final source in ['load', 'page', 'incoming', 'range', 'selection']) {
      test('destination LRU excludes an in-flight $source request', () async {
        final release = controller.retainFeed(site.url, 'visible');
        final visible = controller.load(
          instance: site,
          destinationId: 'visible',
          path: '/visible.json',
          incoming: null,
        );
        await answer([100]);
        await visible;
        if (source != 'load') {
          final first = controller.load(
            instance: site,
            destinationId: 'working',
            path: '/working.json',
            incoming: null,
          );
          await answer([1], next: '/working.json?page=1');
          await first;
        }
        final incoming = IncomingTopics()
          ..track({'working': const IncomingTopicsFilter.latest()})
          ..notify({'message_type': 'new_topic', 'topic_id': 2});
        if (source == 'range') store.forget(site.url);
        final pending = switch (source) {
          'load' => controller.load(
            instance: site,
            destinationId: 'working',
            path: '/working.json',
            incoming: null,
          ),
          'page' => controller.loadMore(
            instance: site,
            destinationId: 'working',
          ),
          'incoming' => controller.showIncoming(
            instance: site,
            destinationId: 'working',
            path: '/working.json',
            incoming: incoming,
          ),
          'selection' => controller.restoreTopic(
            instance: site,
            destinationId: 'working',
            topicId: 2,
          ),
          _ => controller.ensureRange(
            instance: site,
            destinationId: 'working',
            firstRow: 0,
            lastRow: 0,
          ),
        };
        await pumpEventQueue();
        final activeRequest = api.requests.last;
        final third = controller.load(
          instance: site,
          destinationId: 'third',
          path: '/third.json',
          incoming: null,
        );
        await answer([3]);
        await third;
        expect(controller.feedFor(site.url, 'visible'), isNotNull);
        expect(controller.feedFor(site.url, 'third'), isNull);
        activeRequest.response.complete(_page(source == 'range' ? 1 : 2));
        await pending;
        expect(controller.feedFor(site.url, 'working'), isNotNull);
        release();
      });
    }
  });

  group('incoming topics', () {
    test('requests and clears one server page at a time', () async {
      final site = instance('one.example');
      final initial = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await pumpEventQueue();
      api.requests.single.response.complete(_page(100));
      await initial;

      final incoming = IncomingTopics();
      for (var id = 1; id <= TopicFeedController.incomingPageSize + 1; id++) {
        incoming.notify({'topic_id': id, 'message_type': 'latest'});
      }

      final load = controller.showIncoming(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: incoming,
      );
      await pumpEventQueue();

      final requestedIds = [
        for (var id = 1; id <= TopicFeedController.incomingPageSize; id++) id,
      ];
      expect(api.requests, hasLength(2));
      expect(
        api.requests.last.path,
        '/latest.json?topic_ids=${requestedIds.join(',')}',
      );
      api.requests.last.response.complete(_pages(requestedIds));
      await load;

      expect(controller.feedFor(site.url, 'latest')?.topicIds, [
        ...requestedIds,
        100,
      ]);
      expect(incoming.topicIds('latest'), [31]);
      expect(incoming.count('latest'), 1);
    });

    test('asks for them within the list, keeping its own query', () async {
      final site = instance('one.example');
      const path = '/latest.json?category=5&tags%5B%5D=ux';
      final initial = controller.load(
        instance: site,
        destinationId: 'filtered',
        path: path,
        incoming: null,
      );
      await pumpEventQueue();
      api.requests.single.response.complete(_page(100));
      await initial;
      final incoming = IncomingTopics()
        ..track({'filtered': const IncomingTopicsFilter.latest()})
        ..notify({'topic_id': 7, 'message_type': 'latest'});

      final load = controller.showIncoming(
        instance: site,
        destinationId: 'filtered',
        path: path,
        incoming: incoming,
      );
      await pumpEventQueue();

      expect(api.requests.last.path, '$path&topic_ids=7');
      api.requests.last.response.complete(_page(7));
      await load;

      expect(controller.feedFor(site.url, 'filtered')?.topicIds, [7, 100]);
      expect(incoming.count('filtered'), 0);
    });

    test('records what each loaded list announces', () async {
      final site = instance('one.example');
      final other = instance('two.example');
      final resolved = <String, IncomingTopicsFilter?>{
        '/c/five/5.json': const IncomingTopicsFilter.latest(categoryId: 5),
        '/c/eight/8.json': const IncomingTopicsFilter.latest(categoryId: 8),
        '/top.json': null,
      };
      controller.dispose();
      controller = TopicFeedController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
        store: store,
        incomingFilterFor: (path, _) => resolved[path],
      );
      Future<void> load(
        DiscourseInstance site,
        String destination,
        String path, {
        bool fail = false,
      }) async {
        final loading = controller.load(
          instance: site,
          destinationId: destination,
          path: path,
          incoming: null,
          force: true,
        );
        await pumpEventQueue();
        final response = api.requests.last.response;
        if (fail) {
          response.completeError(
            SiteLookupException(SiteLookupFailure.unreachable, site.url),
          );
        } else {
          response.complete(_page(1));
        }
        await loading;
      }

      await load(site, 'category-5', '/c/five/5.json');
      await load(site, 'category-8', '/c/eight/8.json');
      await load(site, 'top', '/top.json');
      await load(other, 'category-5', '/c/five/5.json');
      expect(controller.incomingFiltersFor(site.url), {
        'category-5': const IncomingTopicsFilter.latest(categoryId: 5),
        'category-8': const IncomingTopicsFilter.latest(categoryId: 8),
      });

      // A failed refetch keeps what the list last announced; a fresh load
      // makes it the most recent.
      await load(site, 'category-5', '/c/five/5.json', fail: true);
      expect(controller.incomingFiltersFor(site.url).keys, [
        'category-5',
        'category-8',
      ]);
      await load(site, 'category-5', '/c/five/5.json');
      expect(controller.incomingFiltersFor(site.url).keys, [
        'category-8',
        'category-5',
      ]);

      // A list whose response no longer announces anything stops counting.
      resolved['/c/eight/8.json'] = null;
      await load(site, 'category-8', '/c/eight/8.json');
      expect(controller.incomingFiltersFor(site.url).keys, ['category-5']);

      controller.forget(site.url);
      expect(controller.incomingFiltersFor(site.url), isEmpty);
      expect(controller.incomingFiltersFor(other.url).keys, ['category-5']);
    });
  });

  group('request lifecycle', () {
    test('shares the load with a synchronous loading listener', () async {
      final site = instance('one.example');
      Future<void>? duplicate;
      controller.addListener(() {
        if (duplicate != null) return;
        duplicate = controller.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );
      });

      final loading = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      expect(duplicate, same(loading));
      await pumpEventQueue();
      api.requests.single.response.complete(_page(1));
      await loading;
      expect(controller.feedFor(site.url, 'latest')?.topicIds, [1]);
    });

    test('forgetting during loading does not block a new account', () async {
      final site = instance('one.example');
      final gated = _FirstGatedCredentialReader();
      addTearDown(() {
        if (!gated.result.isCompleted) gated.result.complete('old-key');
      });
      final guarded = TopicFeedController(
        api: api,
        credentials: gated,
        lifecycle: SiteLifecycle(),
        store: store,
      );
      addTearDown(guarded.dispose);
      var forgotten = false;
      guarded.addListener(() {
        if (forgotten) return;
        forgotten = true;
        guarded.forget(site.url);
      });
      final old = guarded.load(
        instance: site,
        destinationId: 'latest',
        path: '/old.json',
        incoming: null,
      );
      await gated.started.future;
      final replacement = guarded.load(
        instance: site,
        destinationId: 'latest',
        path: '/replacement.json',
        incoming: null,
      );
      await pumpEventQueue();

      expect(api.requests.map((request) => request.path), [
        '/replacement.json',
      ]);
      api.requests.single.response.complete(_page(2));
      await replacement;
      gated.result.complete('old-key');
      await old;
      expect(guarded.feedFor(site.url, 'latest')?.topicIds, [2]);
    });

    for (final source in ['initial', 'incoming', 'page']) {
      test(
        '$source stops absorbing rows when a record listener forgets the site',
        () async {
          final site = instance('one.example');
          final incoming = IncomingTopics();
          if (source != 'initial') {
            final first = controller.load(
              instance: site,
              destinationId: 'latest',
              path: '/latest.json',
              incoming: incoming,
            );
            await pumpEventQueue();
            api.requests.single.response.complete(
              _page(1, moreTopicsUrl: '/latest?page=1'),
            );
            await first;
          }
          final row = store.ref<Topic>(site.url, 2);
          var forgotten = false;
          void forget() {
            if (forgotten || row.value == null) return;
            forgotten = true;
            controller.forget(site.url);
            store.forget(site.url);
          }

          row.addListener(forget);
          addTearDown(() => row.removeListener(forget));
          incoming.notify({'message_type': 'new_topic', 'topic_id': 2});
          incoming.notify({'message_type': 'new_topic', 'topic_id': 3});
          final loading = switch (source) {
            'initial' => controller.load(
              instance: site,
              destinationId: 'latest',
              path: '/latest.json',
              incoming: incoming,
            ),
            'incoming' => controller.showIncoming(
              instance: site,
              destinationId: 'latest',
              path: '/latest.json',
              incoming: incoming,
            ),
            _ => controller.loadMore(instance: site, destinationId: 'latest'),
          };
          await pumpEventQueue();
          api.requests.last.response.complete(_pages([2, 3]));
          await loading;

          expect(forgotten, isTrue);
          expect(controller.feedFor(site.url, 'latest'), isNull);
          expect(store.read<Topic>(site.url, 2), isNull);
          expect(store.read<Topic>(site.url, 3), isNull);
        },
      );
    }

    for (final source in ['initial', 'incoming']) {
      test(
        '$source cannot run its completion hook after the site is forgotten',
        () async {
          final site = instance('one.example');
          var completions = 0;
          final guarded = TopicFeedController(
            api: api,
            credentials: credentials,
            lifecycle: SiteLifecycle(),
            store: store,
            onFeedLoaded: (_, _, _, _) => completions++,
          );
          addTearDown(guarded.dispose);
          final incoming = IncomingTopics();
          if (source == 'incoming') {
            final first = guarded.load(
              instance: site,
              destinationId: 'latest',
              path: '/latest.json',
              incoming: incoming,
            );
            await pumpEventQueue();
            api.requests.single.response.complete(_page(1));
            await first;
            completions = 0;
          }
          guarded.addListener(() {
            if (guarded.feedFor(site.url, 'latest')?.topicIds.contains(2) ==
                true) {
              guarded.forget(site.url);
            }
          });
          incoming.notify({'message_type': 'new_topic', 'topic_id': 2});
          final loading = source == 'initial'
              ? guarded.load(
                  instance: site,
                  destinationId: 'latest',
                  path: '/latest.json',
                  incoming: incoming,
                )
              : guarded.showIncoming(
                  instance: site,
                  destinationId: 'latest',
                  path: '/latest.json',
                  incoming: incoming,
                );
          await pumpEventQueue();
          api.requests.last.response.complete(_page(2));
          await loading;

          expect(guarded.feedFor(site.url, 'latest'), isNull);
          expect(completions, 0);
        },
      );
    }

    test(
      'retains existing rows while the next page is being prepared',
      () async {
        final site = instance('one.example');
        final ready = Completer<void>();
        final prepared = TopicFeedController(
          api: api,
          credentials: credentials,
          lifecycle: SiteLifecycle(),
          store: store,
          prepareFeed: (_, _, _, ids) async {
            if (ids.contains(9)) await ready.future;
          },
        );
        addTearDown(prepared.dispose);
        final initial = prepared.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );
        await pumpEventQueue();
        api.requests.single.response.complete(
          _page(1, moreTopicsUrl: '/latest?page=1'),
        );
        await initial;
        final next = prepared.loadMore(instance: site, destinationId: 'latest');
        await pumpEventQueue();
        api.requests.last.response.complete(
          const TopicList(
            topics: [
              Topic(
                id: 2,
                title: 'Second topic',
                slug: 'second-topic',
                categoryId: 9,
              ),
            ],
          ),
        );
        await pumpEventQueue();
        expect(prepared.feedFor(site.url, 'latest')?.topicIds, [1]);
        expect(prepared.feedFor(site.url, 'latest')?.loadingMore, isTrue);
        expect(store.read<Topic>(site.url, 2), isNull);
        ready.complete();
        await next;
        expect(prepared.feedFor(site.url, 'latest')?.topicIds, [1, 2]);
        expect(prepared.feedFor(site.url, 'latest')?.loadingMore, isFalse);
      },
    );

    test(
      'rejects a feed whose site changed while metadata was prepared',
      () async {
        final site = instance('one.example');
        final lifecycle = SiteLifecycle();
        final started = Completer<void>();
        final ready = Completer<void>();
        final prepared = TopicFeedController(
          api: api,
          credentials: credentials,
          lifecycle: lifecycle,
          store: store,
          prepareFeed: (_, _, _, _) {
            started.complete();
            return ready.future;
          },
        );
        addTearDown(prepared.dispose);
        final loading = prepared.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );
        await pumpEventQueue();
        api.requests.single.response.complete(_page(1));
        await started.future;
        lifecycle.invalidate(site.url);
        prepared.forget(site.url);
        ready.complete();
        await loading;
        expect(store.read<Topic>(site.url, 1), isNull);
        expect(prepared.feedFor(site.url, 'latest'), isNull);
      },
    );

    test('replays one forced load after the active request', () async {
      final site = instance('one.example');
      final older = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
        force: true,
      );
      await pumpEventQueue();
      final newer = controller.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
        force: true,
      );
      await pumpEventQueue();

      expect(api.requests, hasLength(1));
      api.requests[0].response.complete(_page(1));
      await older;
      await pumpEventQueue();
      expect(api.requests, hasLength(2));
      api.requests[1].response.complete(_page(2));
      await newer;

      expect(controller.feedFor(site.url, 'latest')?.topicIds, [2]);
      expect(store.read<Topic>(site.url, 1)?.title, 'Topic 1');
      expect(store.read<Topic>(site.url, 2)?.title, 'Topic 2');
    });

    test(
      'suppresses the post-load callback after reentrant disposal',
      () async {
        final site = instance('one.example');
        var loaded = false;
        final guarded = TopicFeedController(
          api: api,
          credentials: credentials,
          lifecycle: SiteLifecycle(),
          store: store,
          onFeedLoaded: (_, _, _, _) => loaded = true,
        );

        final loading = guarded.load(
          instance: site,
          destinationId: 'latest',
          path: '/latest.json',
          incoming: null,
        );
        await pumpEventQueue();
        guarded.addListener(guarded.dispose);

        api.requests.single.response.complete(_page(1));
        await loading;

        expect(loaded, isFalse);
      },
    );
  });

  group('site forgetting', () {
    test('uses exact site keys and rejects a late response', () async {
      final first = instance('one.example');
      final similarlyNamed = instance('one.example.invalid');

      final firstLoad = controller.load(
        instance: first,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await pumpEventQueue();
      api.requests[0].response.complete(_page(1));
      await firstLoad;

      final otherLoad = controller.load(
        instance: similarlyNamed,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await pumpEventQueue();
      api.requests[1].response.complete(_page(2));
      await otherLoad;

      controller
        ..setFilterQuery(first.url, 'first')
        ..setFilterQuery(similarlyNamed.url, 'other')
        ..saveScrollRow(first.url, 'latest', 11)
        ..saveScrollRow(similarlyNamed.url, 'latest', 22);

      final late = controller.load(
        instance: first,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
        force: true,
      );
      await pumpEventQueue();
      controller.forget(first.url);
      api.requests[2].response.complete(_page(3));
      await late;

      expect(controller.feedFor(first.url, 'latest'), isNull);
      expect(controller.filterQueryFor(first.url), isEmpty);
      expect(controller.scrollRowFor(first.url, 'latest'), 0);
      expect(store.read<Topic>(first.url, 3), isNull);

      expect(controller.feedFor(similarlyNamed.url, 'latest')?.topicIds, [2]);
      expect(controller.filterQueryFor(similarlyNamed.url), 'other');
      expect(controller.scrollRowFor(similarlyNamed.url, 'latest'), 22);
    });

    test('prevents HTTP work during a pending credential lookup', () async {
      final site = instance('one.example');
      final gatedCredentials = _GatedCredentialReader();
      final guarded = TopicFeedController(
        api: api,
        credentials: gatedCredentials,
        lifecycle: SiteLifecycle(),
        store: store,
      );
      addTearDown(guarded.dispose);

      final load = guarded.load(
        instance: site,
        destinationId: 'latest',
        path: '/latest.json',
        incoming: null,
      );
      await gatedCredentials.started.future;
      guarded.forget(site.url);
      gatedCredentials.result.complete('stale-key');
      await load;

      expect(api.requests, isEmpty);
      expect(guarded.feedFor(site.url, 'latest'), isNull);
    });
  });
}
