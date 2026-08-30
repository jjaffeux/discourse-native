import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
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

final class _ControlledTopicFeedsApi implements TopicFeedsApi {
  final List<_PendingFeed> requests = [];

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

TopicList _page(int id, {String? moreTopicsUrl}) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
  moreTopicsUrl: moreTopicsUrl,
);

TopicList _pages(Iterable<int> ids) => TopicList(
  topics: [
    for (final id in ids) Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
  ],
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

  tearDown(() => controller.dispose());

  test('a failed initial load offers one coalesced retry', () async {
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

  test('refresh keeps stale rows and scroll state through a failure', () async {
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
  });

  test('a failed next page keeps its cursor and retries once', () async {
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

    final retry = controller.loadMore(instance: site, destinationId: 'latest');
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

  test('a page of already-known topics still advances the cursor', () async {
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

    // The whole page is already on the list — the shape a busy feed takes
    // after the incoming-topics banner prepends the same topics.
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
    expect(api.requests.last.path, contains('page=2'));
    api.requests.last.response.complete(_page(2));
    await nextPage;

    final done = controller.feedFor(site.url, 'latest')!;
    expect(done.topicIds, [1, 2]);
    expect(done.hasMore, isFalse);
  });

  test('a page that repeats its own cursor ends pagination', () async {
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

  test(
    'incoming topics are requested and cleared one server page at a time',
    () async {
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
    },
  );

  test('a forced load replays once after the active request', () async {
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

  test('reentrant disposal suppresses the feed post-load callback', () async {
    final site = instance('one.example');
    var loaded = false;
    final guarded = TopicFeedController(
      api: api,
      credentials: credentials,
      lifecycle: SiteLifecycle(),
      store: store,
      onFeedLoaded: (_, _, _) => loaded = true,
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
  });

  test('forget uses exact site keys and rejects a late response', () async {
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

  test('forget during credential lookup prevents the HTTP request', () async {
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
}
