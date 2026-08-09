import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
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

TopicList _page(int id) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
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

  test('only the newest whole-list request can publish records', () async {
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

    api.requests[1].response.complete(_page(2));
    await newer;
    api.requests[0].response.complete(_page(1));
    await older;

    expect(controller.feedFor(site.url, 'latest')?.topicIds, [2]);
    expect(store.read<Topic>(site.url, 1), isNull);
    expect(store.read<Topic>(site.url, 2)?.title, 'Topic 2');
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
