import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

final class _PredicateAwareApi extends FakeDiscourseApi {
  _PredicateAwareApi(this.rootPath, {this.pageSize = 2, this.totalPages = 2});

  final String rootPath;
  final int pageSize;
  final int totalPages;
  final List<int> hydrated = [];
  final Set<int> readIds = {};
  Completer<void>? hydrationGate;

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    final firstPage = uri.path == '/search.json' ? 1 : 0;
    final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? firstPage;
    final requested = uri.queryParameters['topic_ids']
        ?.split(',')
        .map(int.parse)
        .toSet();
    final ignoresIds = uri.path == '/filter.json' || uri.path == '/search.json';
    final candidates = [
      for (var id = 1; id <= totalPages * pageSize; id++)
        if ((ignoresIds || requested == null || requested.contains(id)) &&
            (!uri.path.contains('unread') || !readIds.contains(id)))
          id,
    ];
    final offset = (page - firstPage) * pageSize;
    final ids = candidates.skip(offset).take(pageSize);
    return TopicList(
      topics: [for (final id in ids) _topic(id)],
      moreTopicsUrl: candidates.length > offset + pageSize
          ? uri
                .replace(
                  queryParameters: {
                    ...uri.queryParameters,
                    'page': '${page + 1}',
                  },
                )
                .toString()
          : null,
    );
  }

  @override
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    hydrated.add(id);
    await hydrationGate?.future;
    return _topic(id);
  }

  Topic _topic(int id) => Topic(
    id: id,
    title: 'Topic $id',
    slug: 'topic-$id',
    privateMessage: rootPath.contains('private-messages'),
    lastReadPostNumber: readIds.contains(id) ? 5 : 1,
    highestPostNumber: 5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final truncating in [false, true]) {
    test(
      'retains the reader anchor when unread replay ${truncating ? 'truncates' : 'moves'} rows',
      () async {
        final site = instance('one.example');
        final api = _PredicateAwareApi('/unread.json', totalPages: 6);
        final store = Store();
        final readerId = truncating ? 9 : 1;
        final controller = TopicFeedController(
          api: api,
          credentials: FakeApiCredentialReader(),
          lifecycle: SiteLifecycle(),
          store: store,
          readerTopics: (_, _) => {readerId},
          maximumRetainedTopics: 4,
          maximumCursorCheckpoints: 2,
        );
        addTearDown(controller.dispose);
        await controller.load(
          instance: site,
          destinationId: 'feed',
          path: '/unread.json',
          incoming: null,
        );
        for (var page = 1; page < 6; page++) {
          await controller.loadMore(instance: site, destinationId: 'feed');
        }
        expect(
          controller.feedFor(site.url, 'feed')!.indexOfTopic(readerId),
          readerId - 1,
        );
        api.readIds.addAll(
          truncating ? [for (var id = 2; id <= 12; id++) id] : [1],
        );
        final target = truncating ? 0 : 1;
        await controller.ensureRange(
          instance: site,
          destinationId: 'feed',
          firstRow: target,
          lastRow: target,
        );
        final feed = controller.feedFor(site.url, 'feed')!;
        expect(feed.error, isNotNull);
        expect(feed.indexOfTopic(readerId), readerId - 1);
        expect(feed.rowCount, 12);
      },
    );
  }

  for (final rootPath in [
    '/filter.json?q=tag:one',
    '/search.json?q=one&page=1',
    '/unread.json',
    '/topics/private-messages-unread/sam.json',
  ]) {
    test(
      'hydrates a selected ID independently of $rootPath predicates',
      () async {
        final site = instance('one.example');
        final api = _PredicateAwareApi(rootPath);
        final store = Store();
        final controller = TopicFeedController(
          api: api,
          credentials: FakeApiCredentialReader(),
          lifecycle: SiteLifecycle(),
          store: store,
        );
        addTearDown(controller.dispose);
        await controller.load(
          instance: site,
          destinationId: 'feed',
          path: rootPath,
          incoming: null,
        );
        await controller.loadMore(instance: site, destinationId: 'feed');
        api.readIds.add(3);
        store.forget(site.url);
        final restored = await controller.restoreTopic(
          instance: site,
          destinationId: 'feed',
          topicId: 3,
        );
        expect(restored?.id, 3);
        expect(restored?.privateMessage, rootPath.contains('private-messages'));
        expect(api.hydrated, [3]);
      },
    );

    test(
      'hydrates retained rows independently of $rootPath predicates',
      () async {
        final site = instance('one.example');
        final api = _PredicateAwareApi(rootPath);
        final store = Store();
        final controller = TopicFeedController(
          api: api,
          credentials: FakeApiCredentialReader(),
          lifecycle: SiteLifecycle(),
          store: store,
        );
        addTearDown(controller.dispose);
        await controller.load(
          instance: site,
          destinationId: 'feed',
          path: rootPath,
          incoming: null,
        );
        await controller.loadMore(instance: site, destinationId: 'feed');
        api.readIds.add(3);
        store.forget(site.url);
        await controller.ensureRange(
          instance: site,
          destinationId: 'feed',
          firstRow: 2,
          lastRow: 3,
        );
        expect(controller.feedFor(site.url, 'feed')?.error, isNull);
        expect(store.read<Topic>(site.url, 3)?.id, 3);
        expect(store.read<Topic>(site.url, 4)?.id, 4);
        expect(api.hydrated, [3, 4]);
      },
    );
  }

  test('hydrates a retained range larger than one server list page', () async {
    final site = instance('one.example');
    final api = _PredicateAwareApi('/latest.json', pageSize: 30);
    final store = Store();
    final controller = TopicFeedController(
      api: api,
      credentials: FakeApiCredentialReader(),
      lifecycle: SiteLifecycle(),
      store: store,
    );
    addTearDown(controller.dispose);
    await controller.load(
      instance: site,
      destinationId: 'feed',
      path: '/latest.json',
      incoming: null,
    );
    await controller.loadMore(instance: site, destinationId: 'feed');
    store.forget(site.url);
    await controller.ensureRange(
      instance: site,
      destinationId: 'feed',
      firstRow: 0,
      lastRow: 59,
    );
    expect(controller.feedFor(site.url, 'feed')?.error, isNull);
    expect(api.hydrated, [for (var id = 1; id <= 60; id++) id]);
    expect(
      [for (var id = 1; id <= 60; id++) store.read<Topic>(site.url, id)?.id],
      [for (var id = 1; id <= 60; id++) id],
    );
  });

  test(
    'stops a range hydration before dispatching another ID after logout',
    () async {
      final site = instance('one.example');
      final api = _PredicateAwareApi('/latest.json');
      final store = Store();
      final lifecycle = SiteLifecycle();
      final controller = TopicFeedController(
        api: api,
        credentials: FakeApiCredentialReader(),
        lifecycle: lifecycle,
        store: store,
      );
      addTearDown(controller.dispose);
      await controller.load(
        instance: site,
        destinationId: 'feed',
        path: '/latest.json',
        incoming: null,
      );
      store.forget(site.url);
      api.hydrationGate = Completer<void>();
      final restoring = controller.ensureRange(
        instance: site,
        destinationId: 'feed',
        firstRow: 0,
        lastRow: 1,
      );
      await pumpEventQueue();
      lifecycle.invalidate(site.url);
      api.hydrationGate!.complete();
      await restoring;
      expect(api.hydrated, [1]);
      expect(store.containsRecord<Topic>(site.url, 1), isFalse);
    },
  );
}
