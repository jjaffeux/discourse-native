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

  group('request admission', () {
    test(
      'a loading listener shares the refresh already being admitted',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final response = fixture.api.hold(0);
        Future<void>? repeated;
        var reentered = false;
        fixture.controller.addListener(() {
          if (!fixture.controller.state.loading || reentered) return;
          reentered = true;
          repeated = fixture.controller.refresh(const [_first]);
        });

        final refresh = fixture.controller.refresh(const [_first]);
        expect(identical(repeated, refresh), isTrue);
        await pumpEventQueue();
        expect(fixture.api.requests, hasLength(1));
        response.complete(TopicList(topics: [_topic(1)]));
        await refresh;
        expect(fixture.controller.state.topics.single.topicId, 1);
      },
    );

    test('refresh ownership precedes its loading notification', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      var invalidated = false;
      fixture.controller.addListener(() {
        if (!fixture.controller.state.loading || invalidated) return;
        invalidated = true;
        fixture.lifecycle.invalidate(_first.url);
      });

      await fixture.controller.refresh(const [_first]);

      expect(fixture.credentials.reads, isEmpty);
      expect(fixture.api.requests, isEmpty);
    });

    test('disposal from a loading listener stops credential reads', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.controller.addListener(fixture.dispose);

      await fixture.controller.refresh(const [_first]);

      expect(fixture.credentials.reads, isEmpty);
      expect(fixture.api.requests, isEmpty);
    });

    test('retained loading commands stop after disposal', () async {
      final fixture = _Fixture();
      fixture.dispose();

      await fixture.controller.open(const [_first]);
      await fixture.controller.refresh(const [_first]);
      await fixture.controller.loadMore();

      expect(fixture.credentials.reads, isEmpty);
      expect(fixture.api.requests, isEmpty);
    });
  });

  group('queued transport ownership', () {
    test(
      'an expired forum does not dispatch after waiting for a slot',
      () async {
        final fixture = _Fixture(maximumConcurrentRequests: 1);
        addTearDown(fixture.dispose);
        final response = fixture.api.hold(0);
        final refresh = fixture.controller.refresh(const [_first, _second]);
        await pumpEventQueue();
        expect(fixture.api.requests.map((request) => request.siteUrl), [
          _first.url,
        ]);
        fixture.lifecycle.invalidate(_second.url);
        response.complete(TopicList(topics: [_topic(1)]));
        await refresh;

        expect(fixture.api.requests.map((request) => request.siteUrl), [
          _first.url,
        ]);
        expect(fixture.controller.state.topics, [
          AggregateTopicRef(siteUrl: _first.url, topicId: 1),
        ]);
      },
    );

    test('a forced replacement skips the old queued forum request', () async {
      final fixture = _Fixture(maximumConcurrentRequests: 1);
      addTearDown(fixture.dispose);
      final response = fixture.api.hold(0);
      final initial = fixture.controller.refresh(const [_first, _second]);
      await pumpEventQueue();
      final replacement = fixture.controller.refresh(const [
        _first,
      ], force: true);
      await pumpEventQueue();
      response.complete(TopicList(topics: [_topic(1)]));
      await Future.wait([initial, replacement]);

      expect(fixture.api.requests.map((request) => request.siteUrl), [
        _first.url,
        _first.url,
      ]);
      expect(fixture.controller.state.failures, isEmpty);
    });
  });

  group('account forgetting', () {
    test(
      'forgetting preserves other rows and refreshes on the next open',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        await fixture.controller.setForumFilters(
          allForums: const [_first, _second],
          includedConnectedForums: {_first.url, _second.url},
          queries: {_second.url: 'status:open'},
        );
        fixture.api.replies[0] = TopicList(topics: [_topic(1)]);
        fixture.api.replies[1] = TopicList(topics: [_topic(2)]);
        await fixture.controller.refresh(const [_first, _second]);

        fixture.controller.forget(_first.url);

        expect(fixture.controller.state.topics, [
          AggregateTopicRef(siteUrl: _second.url, topicId: 2),
        ]);
        expect(fixture.controller.queryFor(_second.url), 'status:open');
        expect(fixture.controller.state.includedForums, 1);
        fixture.api.replies[2] = TopicList(topics: [_topic(3)]);
        await fixture.controller.open(const [_second]);
        expect(fixture.controller.state.topics, [
          AggregateTopicRef(siteUrl: _second.url, topicId: 3),
        ]);
      },
    );

    test(
      'forgetting a pending forum permits an immediate replacement',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final response = fixture.api.hold(0);
        final initial = fixture.controller.refresh(const [_first]);
        await pumpEventQueue();

        fixture.controller.forget(_first.url);
        fixture.api.replies[1] = TopicList(topics: [_topic(9)]);
        await fixture.controller.refresh(const [_first]);
        response.complete(TopicList(topics: [_topic(1)]));
        await initial;

        expect(fixture.controller.state.topics, [
          AggregateTopicRef(siteUrl: _first.url, topicId: 9),
        ]);
        expect(fixture.store.read<Topic>(_first.url, 1), isNull);
      },
    );

    test('forgetting an unrelated forum preserves the pending tab', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      final response = fixture.api.hold(0);
      final refresh = fixture.controller.refresh(const [_first]);
      await pumpEventQueue();
      fixture.controller.forget(_second.url);
      response.complete(TopicList(topics: [_topic(1)]));
      await refresh;

      expect(fixture.controller.state.topics, [
        AggregateTopicRef(siteUrl: _first.url, topicId: 1),
      ]);
      expect(fixture.controller.state.loading, isFalse);
    });
  });

  group('record publication', () {
    test(
      'a preparation callback cannot publish after expiring its account',
      () async {
        final lifecycle = SiteLifecycle();
        final fixture = _Fixture(
          lifecycle: lifecycle,
          prepareTopic: (siteUrl, topic, _) {
            lifecycle.invalidate(siteUrl);
            return topic;
          },
        );
        addTearDown(fixture.dispose);
        fixture.api.replies[0] = TopicList(topics: [_topic(1), _topic(2)]);

        await fixture.controller.refresh(const [_first]);

        expect(fixture.store.read<Topic>(_first.url, 1), isNull);
        expect(fixture.store.read<Topic>(_first.url, 2), isNull);
        expect(fixture.controller.state.topics, isEmpty);
      },
    );

    test(
      'a store observer can forget a forum while rows are published',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        final first = fixture.store.ref<Topic>(_first.url, 1);
        var forgotten = false;
        first.addListener(() {
          if (first.value == null || forgotten) return;
          forgotten = true;
          fixture.lifecycle.invalidate(_first.url);
          fixture.store.forget(_first.url);
        });
        fixture.api.replies[0] = TopicList(topics: [_topic(1), _topic(2)]);

        await fixture.controller.refresh(const [_first]);

        expect(fixture.store.read<Topic>(_first.url, 1), isNull);
        expect(fixture.store.read<Topic>(_first.url, 2), isNull);
        expect(fixture.controller.state.topics, isEmpty);
      },
    );
  });

  group('pagination ownership', () {
    test(
      'a forced refresh releases pagination from the previous feed',
      () async {
        final fixture = _Fixture(batchSize: 1);
        addTearDown(fixture.dispose);
        fixture.api.replies[0] = TopicList(
          topics: [_topic(1)],
          moreTopicsUrl: '/filter.json?page=1',
        );
        await fixture.controller.refresh(const [_first]);
        final oldResponse = fixture.api.hold(1);
        final oldPage = fixture.controller.loadMore();
        await pumpEventQueue();
        fixture.api.replies[2] = TopicList(
          topics: [_topic(3)],
          moreTopicsUrl: '/filter.json?page=1',
        );
        await fixture.controller.refresh(const [_first], force: true);
        fixture.api.replies[3] = TopicList(topics: [_topic(4)]);

        final newPage = fixture.controller.loadMore();
        expect(identical(newPage, oldPage), isFalse);
        await newPage;
        expect(fixture.controller.state.topics.map((topic) => topic.topicId), [
          3,
          4,
        ]);
        oldResponse.complete(TopicList(topics: [_topic(2)]));
        await oldPage;
        expect(fixture.controller.state.topics.map((topic) => topic.topicId), [
          3,
          4,
        ]);
      },
    );

    for (final duplicate in [false, true]) {
      test(
        'a cursor cycle stops when later pages are ${duplicate ? 'duplicates' : 'empty'}',
        () async {
          final fixture = _Fixture();
          addTearDown(fixture.dispose);
          fixture.api.replies[0] = TopicList(
            topics: [_topic(1)],
            moreTopicsUrl: '/filter.json?page=1',
          );
          fixture.api.replies[1] = TopicList(
            topics: duplicate ? [_topic(1)] : const [],
            moreTopicsUrl: '/filter.json?page=2',
          );
          fixture.api.replies[2] = TopicList(
            topics: duplicate ? [_topic(1)] : const [],
            moreTopicsUrl: '/filter.json?page=1',
          );

          await fixture.controller.refresh(const [_first]);

          expect(fixture.api.requests.map((request) => request.path), [
            '/filter.json?per_page=30',
            '/filter.json?page=1',
            '/filter.json?page=2',
          ]);
          expect(
            fixture.controller.state.topics.map((topic) => topic.topicId),
            [1],
          );
          expect(fixture.controller.state.hasMore, isFalse);
        },
      );
    }

    test('concurrent pagination callers share completion', () async {
      final fixture = _Fixture(batchSize: 1);
      addTearDown(fixture.dispose);
      fixture.api.replies[0] = TopicList(
        topics: [_topic(1)],
        moreTopicsUrl: '/filter.json?page=1',
      );
      await fixture.controller.refresh(const [_first]);
      final response = fixture.api.hold(1);

      final more = fixture.controller.loadMore();
      final repeated = fixture.controller.loadMore();
      expect(identical(more, repeated), isTrue);
      await pumpEventQueue();
      response.complete(TopicList(topics: [_topic(2)]));
      await more;
      expect(fixture.controller.state.topics.map((topic) => topic.topicId), [
        1,
        2,
      ]);
    });

    test('buffered topics expire with their original account', () async {
      final fixture = _Fixture(batchSize: 1);
      addTearDown(fixture.dispose);
      fixture.api.replies[0] = TopicList(topics: [_topic(1), _topic(2)]);
      await fixture.controller.refresh(const [_first]);
      final firstPage = fixture.controller.state.topics;
      expect(firstPage, hasLength(1));
      fixture.lifecycle.invalidate(_first.url);

      await fixture.controller.loadMore();

      expect(fixture.controller.state.topics, firstPage);
      expect(fixture.controller.state.hasMore, isFalse);
      expect(fixture.api.requests, hasLength(1));
    });

    test(
      'an expired page does not retry with its retained credential',
      () async {
        final fixture = _Fixture(batchSize: 1);
        addTearDown(fixture.dispose);
        fixture.api.replies[0] = TopicList(
          topics: [_topic(1)],
          moreTopicsUrl: '/filter.json?page=1',
        );
        await fixture.controller.refresh(const [_first]);
        final response = fixture.api.hold(1);
        final more = fixture.controller.loadMore();
        await pumpEventQueue();
        fixture.lifecycle.invalidate(_first.url);
        response.complete(
          TopicList(topics: [_topic(2)], moreTopicsUrl: '/filter.json?page=2'),
        );
        await more;

        expect(fixture.api.requests, hasLength(2));
        expect(fixture.controller.state.topics.map((topic) => topic.topicId), [
          1,
        ]);
        expect(fixture.controller.state.hasMore, isFalse);
      },
    );
  });
}

final class _Fixture {
  _Fixture({
    SiteLifecycle? lifecycle,
    AggregateTopicPreparer? prepareTopic,
    int batchSize = 30,
    int maximumConcurrentRequests = 4,
  }) : lifecycle = lifecycle ?? SiteLifecycle() {
    controller = AggregateFeedController(
      api: api,
      credentials: credentials,
      lifecycle: this.lifecycle,
      store: store,
      preferences: AggregatePreferencesStore.memory(),
      readPersonalizationVersion: (_) => 0,
      prepareTopic: prepareTopic ?? (_, topic, _) => topic,
      batchSize: batchSize,
      maximumConcurrentRequests: maximumConcurrentRequests,
    );
  }

  final _ControlledApi api = _ControlledApi();
  final _Credentials credentials = _Credentials();
  final SiteLifecycle lifecycle;
  final Store store = Store();
  late final AggregateFeedController controller;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    for (final response in api.responses.values) {
      if (!response.isCompleted) response.complete(const TopicList(topics: []));
    }
  }
}

final class _Credentials extends FakeApiCredentialReader {
  final List<String> reads = [];

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    reads.add(siteUrl);
    return 'key-for-$siteUrl';
  }
}

typedef _Request = ({String siteUrl, String path, String? apiKey});

final class _ControlledApi extends FakeDiscourseApi {
  final List<_Request> requests = [];
  final Map<int, Completer<TopicList>> responses = {};
  final Map<int, TopicList> replies = {};

  Completer<TopicList> hold(int index) => responses[index] = Completer();

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final index = requests.length;
    requests.add((siteUrl: siteUrl, path: path, apiKey: apiKey));
    return responses[index]?.future ??
        Future.value(replies[index] ?? const TopicList(topics: []));
  }
}

Topic _topic(int id) => Topic(id: id, title: 'Topic $id', slug: 'topic-$id');
