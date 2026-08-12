import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_feed.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';

void main() {
  final sites = [instance('one.example'), instance('two.example')];

  testWidgets('failed first load retries once from the empty state', (
    tester,
  ) async {
    final api = _ControlledPagingApi();
    final controller = await _controlledShell(api, sites.first);
    addTearDown(controller.dispose);

    api.requests.single.response.completeError(
      SiteLookupException(SiteLookupFailure.unreachable, sites.first.url),
    );
    await tester.pump();
    await tester.pumpWidget(_LiveTestList(controller: controller));
    await tester.pump();

    expect(find.text("Couldn't reach one.example."), findsOneWidget);
    final retry = find.byKey(const ValueKey('topic-feed-initial-retry'));
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.tap(retry);
    await tester.pump();
    expect(api.requests, hasLength(2));

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(retry, findsNothing);

    api.requests.last.response.complete(_page(1));
    await tester.pumpAndSettle();

    expect(find.text('Topic 1'), findsOneWidget);
    expect(api.requests, hasLength(2));
  });

  testWidgets('stale rows expose refresh and page retry states', (
    tester,
  ) async {
    final api = _ControlledPagingApi();
    final controller = await _controlledShell(api, sites.first);
    addTearDown(controller.dispose);

    api.requests.single.response.complete(_page(1));
    await tester.pump();
    await tester.pumpWidget(_LiveTestList(controller: controller));
    await tester.pump();

    final beforeRefresh = api.requests.length;
    final refresh = controller.loadFeed('latest', force: true);
    await tester.pump();
    expect(api.requests, hasLength(beforeRefresh + 1));

    expect(find.text('Topic 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-refresh-progress')),
      findsOneWidget,
    );

    api.requests.last.response.completeError(Exception('offline'));
    await refresh;
    await tester.pump();

    expect(find.text('Topic 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-refresh-error')),
      findsOneWidget,
    );

    final refreshRetry = find.descendant(
      of: find.byKey(const ValueKey('topic-feed-refresh-error')),
      matching: find.byKey(const ValueKey('topic-feed-error-retry')),
    );
    final beforeRefreshRetry = api.requests.length;
    await tester.tap(refreshRetry);
    await tester.tap(refreshRetry);
    await tester.pump();
    expect(api.requests, hasLength(beforeRefreshRetry + 1));
    api.requests.last.response.complete(
      _page(2, moreTopicsUrl: '/latest?page=1'),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(api.requests, hasLength(beforeRefreshRetry + 2));

    api.requests.last.response.completeError(Exception('offline'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Topic 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-load-more-error')),
      findsOneWidget,
    );

    final pageRetry = find.descendant(
      of: find.byKey(const ValueKey('topic-feed-load-more-error')),
      matching: find.byKey(const ValueKey('topic-feed-error-retry')),
    );
    final beforePageRetry = api.requests.length;
    await tester.tap(pageRetry);
    await tester.tap(pageRetry);
    await tester.pump();
    expect(api.requests, hasLength(beforePageRetry + 1));

    api.requests.last.response.complete(_page(3));
    await tester.pump();
    await tester.pump();

    expect(find.text('Topic 2'), findsOneWidget);
    expect(find.text('Topic 3'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-feed-load-more-error')),
      findsNothing,
    );
  });

  testWidgets('the same destination has an independent position per site', (
    tester,
  ) async {
    final topics = _topics(1, 40);
    final controller = ShellController(
      instanceStore: FakeInstanceStore(sites),
      api: FakeDiscourseApi(feeds: {'/latest.json': topics}),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    controller.store
      ..putAll(sites[0].url, topics)
      ..putAll(sites[1].url, topics);
    final feed = TopicFeed(
      topicIds: [for (final topic in topics) topic.id],
      loaded: true,
    );

    await tester.pumpWidget(_TestList(controller: controller, feed: feed));
    await tester.pumpAndSettle();

    final first = tester.widget<SuperListView>(find.byType(SuperListView));
    await tester.drag(find.byType(SuperListView), const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(first.controller!.offset, greaterThan(0));

    controller.selectInstance(1);
    await tester.pump();

    final second = tester.widget<SuperListView>(find.byType(SuperListView));
    expect(second.controller, isNot(same(first.controller)));
    expect(second.controller!.offset, 0);
  });

  testWidgets('a queued page request cannot cross a site switch', (
    tester,
  ) async {
    final api = _PagingApi();
    final controller = ShellController(
      instanceStore: FakeInstanceStore(sites),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pump();
    controller.selectInstance(1);
    await tester.pump();
    controller.selectInstance(0);
    await tester.pump();
    expect(controller.currentFeed?.hasMore, isTrue);
    expect(api.pageSites, isEmpty);

    var showList = false;
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
                return showList
                    ? TopicListView(feed: controller.currentFeed!)
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.selectInstance(1);
      rebuild(() => showList = false);
    });
    rebuild(() => showList = true);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.pageSites, isNot(contains(sites[1].url)));
  });
}

final class _TestList extends StatelessWidget {
  const _TestList({required this.controller, required this.feed});

  final ShellController controller;
  final TopicFeed feed;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: TopicListView(feed: feed)),
    ),
  );
}

final class _LiveTestList extends StatelessWidget {
  const _LiveTestList({required this.controller});

  final ShellController controller;

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ShellSelector<TopicFeed?>(
          select: (controller) => controller.currentFeed,
          builder: (context, feed, _) => feed == null
              ? const SizedBox.shrink()
              : TopicListView(feed: feed),
        ),
      ),
    ),
  );
}

final class _PendingTopicPage {
  _PendingTopicPage(this.path);

  final String path;
  final Completer<TopicList> response = Completer<TopicList>();
}

final class _ControlledPagingApi extends FakeDiscourseApi {
  final List<_PendingTopicPage> requests = [];
  Completer<void> _requestsChanged = Completer<void>();

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final request = _PendingTopicPage(path);
    requests.add(request);
    _requestsChanged.complete();
    _requestsChanged = Completer<void>();
    return request.response.future;
  }

  Future<void> waitForRequests(int count) async {
    while (requests.length < count) {
      await _requestsChanged.future;
    }
  }
}

Future<ShellController> _controlledShell(
  _ControlledPagingApi api,
  DiscourseInstance site,
) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await controller.load();
  await api.waitForRequests(1);
  return controller;
}

TopicList _page(int id, {String? moreTopicsUrl}) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
  moreTopicsUrl: moreTopicsUrl,
);

final class _PagingApi extends FakeDiscourseApi {
  final List<String> pageSites = [];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    if (path.contains('page=')) {
      pageSites.add(siteUrl);
      return TopicList(topics: _topics(10, 2));
    }
    return TopicList(topics: _topics(1, 3), moreTopicsUrl: '/latest?page=1');
  }
}

List<Topic> _topics(int first, int count) => [
  for (var id = first; id < first + count; id++)
    Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
];
