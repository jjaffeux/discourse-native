import 'dart:async';

import 'package:discourse_native/src/data/aggregate_preferences_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/aggregate_feed_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _first = DiscourseInstance(
  url: 'https://one.example',
  title: 'One',
  user: DiscourseUser(username: 'sam'),
);
const _second = DiscourseInstance(
  url: 'https://two.example',
  title: 'Two',
  user: DiscourseUser(username: 'lee'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fresh cache recovery', () {
    test('reopens an unobserved feed after its topics are evicted', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.api.siteTopics[_first.url] = [_topic(1)];
      await fixture.controller.open(const [_first]);
      final original = fixture.controller.state;
      final row = fixture.store.ref<Topic>(_first.url, 1);
      void observeRow() {}
      row.addListener(observeRow);
      row.removeListener(observeRow);

      fixture.evictTopics(_first.url);
      expect(fixture.store.containsRecord<Topic>(_first.url, 1), isFalse);
      expect(fixture.controller.state, same(original));
      await fixture.controller.open(const [_first]);

      expect(fixture.api.sites, [_first.url, _first.url]);
      expect(fixture.controller.state.topics, [
        AggregateTopicRef(siteUrl: _first.url, topicId: 1),
      ]);
      expect(fixture.store.read<Topic>(_first.url, 1)?.title, 'Topic 1');
      expect(fixture.controller.state.refreshing, isFalse);
      expect(fixture.controller.state.failures, isEmpty);
      expect(fixture.store.statisticsForTesting.entries, 2);
      expect(fixture.store.statisticsForTesting.overCapacity, 0);
    });

    for (final empty in [false, true]) {
      test('reuses an intact ${empty ? 'empty' : 'populated'} feed', () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        fixture.api.siteTopics[_first.url] = empty ? [] : [_topic(1)];
        await fixture.controller.open(const [_first]);
        final original = fixture.controller.state;

        await fixture.controller.open(const [_first]);

        expect(fixture.controller.state, same(original));
        expect(fixture.api.sites, [_first.url]);
        expect(fixture.controller.state.loaded, isTrue);
      });
    }

    test('checks each site when tabs retain the same topic ID', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.api.siteTopics[_first.url] = [_topic(1)];
      fixture.api.siteTopics[_second.url] = [_topic(1)];
      const forums = [_first, _second];
      final firstTab = fixture.controller.activeTabId;
      await fixture.controller.open(forums);

      final secondTab = fixture.controller.createTab()!;
      await fixture.controller.setForumFilters(
        allForums: forums,
        includedConnectedForums: {_second.url},
        queries: {_second.url: 'status:open'},
      );
      await fixture.controller.open(forums);
      final otherState = fixture.controller.state;
      final otherRow = fixture.store.ref<Topic>(_second.url, 1);
      void observeRow() {}
      otherRow.addListener(observeRow);
      addTearDown(() => otherRow.removeListener(observeRow));

      fixture.evictTopics(_first.url);
      expect(fixture.store.containsRecord<Topic>(_first.url, 1), isFalse);
      expect(fixture.store.containsRecord<Topic>(_second.url, 1), isTrue);
      fixture.controller.selectTab(firstTab);
      await fixture.controller.open(forums);

      expect(fixture.api.sites, [
        _first.url,
        _second.url,
        _second.url,
        _first.url,
        _second.url,
      ]);
      expect(fixture.controller.state.topics, [
        AggregateTopicRef(siteUrl: _first.url, topicId: 1),
        AggregateTopicRef(siteUrl: _second.url, topicId: 1),
      ]);
      expect(fixture.store.containsRecord<Topic>(_first.url, 1), isTrue);
      fixture.controller.selectTab(secondTab);
      await fixture.controller.open(forums);
      expect(fixture.controller.state, same(otherState));
      expect(fixture.controller.queryFor(_second.url), 'status:open');
      expect(fixture.controller.excludedForums, {_first.url});
      expect(fixture.api.sites, hasLength(5));
      expect(fixture.store.statisticsForTesting.overCapacity, 0);
    });

    test('coalesces recovery opens and reports refresh failures', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.api.siteTopics[_first.url] = [_topic(1)];
      await fixture.controller.open(const [_first]);
      fixture.evictTopics(_first.url);
      final response = fixture.api.hold(_first.url);

      final recovery = fixture.controller.open(const [_first]);
      final repeated = fixture.controller.open(const [_first]);
      expect(repeated, same(recovery));
      await pumpEventQueue();
      expect(fixture.api.sites, [_first.url, _first.url]);
      expect(fixture.controller.state.refreshing, isTrue);
      response.completeError(StateError('offline'));
      await recovery;

      expect(fixture.controller.state.failures.keys, [_first.url]);
      expect(fixture.controller.state.topics, isEmpty);
      expect(fixture.controller.state.loaded, isTrue);
      expect(fixture.controller.state.refreshing, isFalse);
      expect(fixture.controller.state.loadingMore, isFalse);
    });

    test('drops a recovery response after its account expires', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.api.siteTopics[_first.url] = [_topic(1)];
      await fixture.controller.open(const [_first]);
      fixture.evictTopics(_first.url);
      final response = fixture.api.hold(_first.url);

      final recovery = fixture.controller.open(const [_first]);
      await pumpEventQueue();
      expect(fixture.api.sites, [_first.url, _first.url]);
      fixture.lifecycle.invalidate(_first.url);
      fixture.controller.forget(_first.url);
      fixture.store.forget(_first.url);
      response.complete(TopicList(topics: [_topic(1)]));
      await recovery;

      expect(fixture.controller.state.topics, isEmpty);
      expect(fixture.store.containsRecord<Topic>(_first.url, 1), isFalse);
      expect(fixture.controller.state.failures, isEmpty);
    });
  });

  group('buffered topic recovery', () {
    test(
      'loadMore restores an evicted buffered topic before emitting it',
      () async {
        final fixture = _Fixture(batchSize: 1);
        addTearDown(fixture.dispose);
        fixture.api.siteTopics[_first.url] = [_topic(2), _topic(1)];
        await fixture.controller.open(const [_first]);
        expect(fixture.controller.state.topics.single.topicId, 2);
        final row = fixture.store.ref<Topic>(_first.url, 2);
        void observeRow() {}
        row.addListener(observeRow);
        addTearDown(() => row.removeListener(observeRow));
        fixture.evictTopics(_first.url);
        expect(fixture.store.containsRecord<Topic>(_first.url, 1), isFalse);
        await fixture.controller.open(const [_first]);
        expect(fixture.api.sites, [_first.url]);

        await fixture.controller.loadMore();

        expect(fixture.controller.state.topics.map((topic) => topic.topicId), [
          2,
          1,
        ]);
        expect(fixture.store.read<Topic>(_first.url, 1)?.title, 'Topic 1');
        expect(fixture.store.containsRecord<Topic>(_first.url, 2), isTrue);
        expect(fixture.api.sites, [_first.url]);
        expect(fixture.controller.state.hasMore, isFalse);
        expect(fixture.store.statisticsForTesting.entries, 2);
        expect(fixture.store.statisticsForTesting.overCapacity, 0);
      },
    );

    test(
      'loadMore preserves a newer stored version of a buffered topic',
      () async {
        final fixture = _Fixture(batchSize: 1);
        addTearDown(fixture.dispose);
        fixture.api.siteTopics[_first.url] = [_topic(2), _topic(1)];
        await fixture.controller.open(const [_first]);
        final updated = _topic(1).copyWith(title: 'Updated', bookmarked: true);
        final stored = fixture.store.put(_first.url, updated);

        await fixture.controller.loadMore();

        expect(fixture.store.read<Topic>(_first.url, 1), same(stored));
        expect(fixture.api.sites, [_first.url]);
      },
    );

    test('a restored record observer can expire its source account', () async {
      final fixture = _Fixture(batchSize: 1);
      addTearDown(fixture.dispose);
      fixture.api.siteTopics[_first.url] = [_topic(2), _topic(1)];
      await fixture.controller.open(const [_first]);
      final firstPage = fixture.controller.state.topics;
      fixture.evictTopics(_first.url);
      final row = fixture.store.ref<Topic>(_first.url, 1);
      var expired = false;
      void expireAccount() {
        if (row.value == null) return;
        expired = true;
        fixture.lifecycle.invalidate(_first.url);
        fixture.store.forget(_first.url);
      }

      row.addListener(expireAccount);
      addTearDown(() => row.removeListener(expireAccount));

      await fixture.controller.loadMore();

      expect(expired, isTrue);
      expect(fixture.controller.state.topics, firstPage);
      expect(fixture.store.containsRecord<Topic>(_first.url, 1), isFalse);
      expect(fixture.controller.state.hasMore, isFalse);
      expect(fixture.api.sites, [_first.url]);
    });
  });
}

final class _Fixture {
  _Fixture({int batchSize = 30}) {
    controller = AggregateFeedController(
      api: api,
      credentials: FakeApiCredentialReader()
        ..keys[_first.url] = 'one-key'
        ..keys[_second.url] = 'two-key',
      lifecycle: lifecycle,
      store: store,
      preferences: AggregatePreferencesStore.memory(),
      readPersonalizationVersion: (_) => 0,
      prepareTopic: (_, topic, _) => topic,
      freshness: const Duration(days: 365),
      batchSize: batchSize,
    );
  }

  final _CacheApi api = _CacheApi();
  final Store store = Store(maxEntries: 2);
  final SiteLifecycle lifecycle = SiteLifecycle();
  late final AggregateFeedController controller;

  void evictTopics(String siteUrl) {
    store.put(siteUrl, _topic(100));
    store.put(siteUrl, _topic(101));
    expect(store.statisticsForTesting.recordEvictions, greaterThan(0));
  }

  void dispose() {
    controller.dispose();
    for (final response in api.responses.values) {
      if (!response.isCompleted) response.complete(const TopicList(topics: []));
    }
  }
}

final class _CacheApi extends FakeDiscourseApi {
  final Map<String, List<Topic>> siteTopics = {};
  final Map<String, Completer<TopicList>> responses = {};
  final List<String> sites = [];

  Completer<TopicList> hold(String siteUrl) => responses[siteUrl] = Completer();

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    sites.add(siteUrl);
    return responses[siteUrl]?.future ??
        Future.value(TopicList(topics: siteTopics[siteUrl] ?? const []));
  }
}

Topic _topic(int id) => Topic(id: id, title: 'Topic $id', slug: 'topic-$id');
