import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/plugins/chat/chat_global_search.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:discourse_native/src/shell/global_search_filters.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fakes.dart';

const _site = 'https://example.test';

void main() {
  testWidgets('identical filter consumers share one HTTP read', (tester) async {
    final client = _SearchClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final counted = _CountingLookupApi(api);
    final controller = _controller(api, searchApi: counted);
    addTearDown(controller.dispose);
    final filter = globalSearchFilter('author')!;
    final first = controller.lookupChoices(filter, 'sam');
    final second = controller.lookupChoices(filter, 'sam');
    await tester.pump();
    expect(counted.lookupStarts, 1);
    expect(client.requests, hasLength(1));
    client.requests.single.complete({
      'users': [
        {'username': 'sam', 'name': 'Sam'},
      ],
    });
    expect((await first).single.value, 'sam');
    expect((await second).single.value, 'sam');
    final refresh = controller.lookupChoices(filter, 'sam');
    await tester.pump();
    expect(client.requests, hasLength(2));
    client.requests.last.complete({'users': <Object?>[]});
    expect(await refresh, isEmpty);
  });

  for (final contributed in [false, true]) {
    for (final action in ['configure', 'dispose']) {
      testWidgets(
        '$action cancels pending ${contributed ? 'contributed' : 'core'} filter reads',
        (tester) async {
          final client = _SearchClient();
          final api = DiscourseApi(client: client);
          addTearDown(api.close);
          final controller = _controller(api, chat: contributed);
          await tester.pump();
          final filter = globalSearchFilter(
            contributed ? 'chatChannel' : 'author',
            controller.capabilities,
          )!;
          final pending = controller.lookupChoices(filter, 'sam');
          await tester.pump();
          expect(client.requests, hasLength(1));
          if (action == 'dispose') {
            controller.dispose();
          } else {
            controller.configure(
              siteUrl: _site,
              capabilities: const GlobalSearchCapabilities(
                authenticated: true,
                username: 'new-account',
              ),
            );
            addTearDown(controller.dispose);
          }
          await tester.pump();
          expect(client.requests.single.aborted, isTrue);
          expect(await pending, isEmpty);
        },
      );
    }
  }

  testWidgets(
    'disposing a filter owner leaves another owner of the same HTTP read alive',
    (tester) async {
      final client = _SearchClient();
      final api = DiscourseApi(client: client);
      addTearDown(api.close);
      final lifecycle = SiteLifecycle();
      final first = _controller(api, lifecycle: lifecycle);
      final second = _controller(api, lifecycle: lifecycle);
      addTearDown(second.dispose);
      await tester.pump();
      final filter = globalSearchFilter('author')!;
      final retired = first.lookupChoices(filter, 'sam');
      final live = second.lookupChoices(filter, 'sam');
      await tester.pump();
      expect(client.requests, hasLength(1));
      first.dispose();
      await tester.pump();
      expect(client.requests.single.aborted, isFalse);
      expect(await retired, isEmpty);
      client.requests.single.complete({
        'users': [
          {'username': 'sam'},
        ],
      });
      expect((await live).single.value, 'sam');
    },
  );

  testWidgets('shared filter errors reach both consumers and can retry', (
    tester,
  ) async {
    final client = _SearchClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final controller = _controller(api);
    addTearDown(controller.dispose);
    final filter = globalSearchFilter('author')!;
    final first = controller.lookupChoices(filter, 'sam');
    final second = controller.lookupChoices(filter, 'sam');
    final firstError = expectLater(first, throwsA(isA<SiteLookupException>()));
    final secondError = expectLater(
      second,
      throwsA(isA<SiteLookupException>()),
    );
    await tester.pump();
    expect(client.requests, hasLength(1));
    client.requests.single.response.completeError(StateError('offline'));
    await firstError;
    await secondError;
    final retry = controller.lookupChoices(filter, 'sam');
    await tester.pump();
    expect(client.requests, hasLength(2));
    client.requests.last.complete({
      'users': [
        {'username': 'sam'},
      ],
    });
    expect((await retry).single.value, 'sam');
  });

  testWidgets('superseded searches abort while another owner stays alive', (
    tester,
  ) async {
    final client = _SearchClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final controller = _controller(api)..setScope(GlobalSearchScope.forum);
    addTearDown(controller.dispose);
    controller.setQuery('first');
    await tester.pump(const Duration(milliseconds: 10));
    final unrelated = api.pluginGetJson(
      siteUrl: _site,
      path: '/search.json?q=first&page=1',
      apiKey: 'key',
      clientId: 'test-client',
    );
    await tester.pump();
    expect(client.requests, hasLength(2));
    expect(client.requests[0].request.url, client.requests[1].request.url);

    controller.setQuery('second');
    await tester.pump(const Duration(milliseconds: 10));
    controller.setQuery('newest');
    await tester.pump(const Duration(milliseconds: 10));

    expect(client.requests.map((r) => r.term), [
      'first',
      'first',
      'second',
      'newest',
    ]);
    expect(client.requests[0].aborted, isTrue);
    expect(client.requests[2].aborted, isTrue);
    expect(client.requests[1].aborted, isFalse);
    client.requests.last.complete(_result('Newest result'));
    await tester.pump();
    expect(controller.results.single.title, 'Newest result');
    expect(controller.error, isNull);
    client.requests[1].complete({'topics': <Object?>[]});
    expect(await unrelated, {'topics': <Object?>[]});
  });

  testWidgets('all core and contributed scope reads share owner cancellation', (
    tester,
  ) async {
    final client = _SearchClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final controller = _controller(api, chat: true)
      ..setPageContext(topicId: 42, topicTitle: 'Current topic')
      ..setQuery('first');
    addTearDown(controller.dispose);
    await tester.pump(const Duration(milliseconds: 10));
    final old = client.requests.toList();
    expect(
      old.map((r) => r.request.url.path),
      contains('/chat/api/search.json'),
    );
    expect(old, hasLength(4));

    controller.setQuery('newest');
    await tester.pump(const Duration(milliseconds: 10));
    expect(old.every((r) => r.aborted), isTrue);
    final newest = client.requests.skip(old.length).toList();
    expect(newest, hasLength(4));
    for (final request in newest) {
      request.complete({});
    }
    await tester.pump();
    expect(controller.phase, GlobalSearchPhase.empty);
    expect(controller.error, isNull);
  });

  testWidgets('superseding a pending page aborts it and resets pagination', (
    tester,
  ) async {
    final client = _SearchClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final controller = _controller(api)
      ..setScope(GlobalSearchScope.forum)
      ..setQuery('first');
    addTearDown(controller.dispose);
    await tester.pump(const Duration(milliseconds: 10));
    client.requests.single.complete({
      ..._result('First page'),
      'grouped_search_result': {'more_posts': true},
    });
    await tester.pump();
    expect(controller.hasMore, isTrue);
    controller.loadMore();
    await tester.pump();
    expect(client.requests.last.request.url.queryParameters['page'], '2');
    expect(controller.results.single.title, 'First page');
    controller.setQuery('newest');
    await tester.pump(const Duration(milliseconds: 10));
    expect(client.requests[1].aborted, isTrue);
    expect(client.requests.last.term, 'newest');
    expect(client.requests.last.request.url.queryParameters['page'], '1');
    client.requests.last.complete(_result('Newest result'));
    await tester.pump();
    expect(controller.results.single.title, 'Newest result');
    expect(controller.hasMore, isFalse);
  });

  testWidgets('cancellable forum reads retain the search timeout', (
    tester,
  ) async {
    final client = _SearchClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    Object? failure;
    unawaited(
      api
          .pluginGetJsonCancellable(
            siteUrl: _site,
            path: '/search.json?q=test',
            apiKey: 'key',
            abortTrigger: Completer<void>().future,
          )
          .then<void>(
            (_) {},
            onError: (Object error) {
              failure = error;
            },
          ),
    );
    await tester.pump();
    expect(client.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 11));
    expect(failure, isNull);
    await tester.pump(const Duration(seconds: 20));
    expect(
      failure,
      isA<SiteLookupException>().having(
        (error) => error.cause,
        'cause',
        isA<TimeoutException>(),
      ),
    );
  });

  test('a pre-cancelled search read never reaches HTTP', () async {
    final client = _SearchClient();
    final api = DiscourseApi(client: client);
    addTearDown(api.close);
    final abort = Completer<void>()..complete();
    await expectLater(
      api.pluginGetJsonCancellable(
        siteUrl: _site,
        path: '/search.json?q=test',
        apiKey: 'key',
        abortTrigger: abort.future,
      ),
      throwsA(
        isA<SiteLookupException>().having(
          (error) => error.cause,
          'cause',
          isA<http.RequestAbortedException>(),
        ),
      ),
    );
    expect(client.requests, isEmpty);
  });

  for (final action in ['clear', 'too short', 'account', 'dispose']) {
    testWidgets('$action aborts active search reads', (tester) async {
      final client = _SearchClient();
      final api = DiscourseApi(client: client);
      addTearDown(api.close);
      final lifecycle = SiteLifecycle();
      final controller = _controller(api, lifecycle: lifecycle)
        ..setScope(GlobalSearchScope.forum)
        ..setQuery('first');
      await tester.pump(const Duration(milliseconds: 10));
      expect(client.requests, hasLength(1));
      switch (action) {
        case 'clear':
          controller.setQuery('');
        case 'too short':
          controller.setQuery('a');
        case 'account':
          lifecycle.invalidate(_site);
          controller.configure(
            siteUrl: _site,
            capabilities: const GlobalSearchCapabilities(authenticated: true),
          );
        case 'dispose':
          controller.dispose();
      }
      await tester.pump();
      expect(client.requests.single.aborted, isTrue);
      if (action != 'dispose') {
        expect(controller.results, isEmpty);
        expect(controller.error, isNull);
        controller.dispose();
      }
    });
  }
}

GlobalSearchController _controller(
  DiscourseApi api, {
  bool chat = false,
  SiteLifecycle? lifecycle,
  GlobalSearchApi? searchApi,
}) =>
    GlobalSearchController(
      api: searchApi ?? GlobalSearchApi(transport: api),
      credentials: FakeApiCredentialReader()..keys[_site] = 'key',
      lifecycle: lifecycle ?? SiteLifecycle(),
      debounceDuration: const Duration(milliseconds: 1),
    )..configure(
      siteUrl: _site,
      capabilities: GlobalSearchCapabilities(
        authenticated: true,
        contributions: [if (chat) const ChatGlobalSearch()],
        enabledContributions: {if (chat) 'chat'},
      ),
    );

Map<String, dynamic> _result(String title) => {
  'posts': [
    {'id': 1, 'topic_id': 42, 'post_number': 1, 'blurb': 'A result'},
  ],
  'topics': [
    {'id': 42, 'title': title, 'slug': 'result'},
  ],
};

class _SearchClient extends http.BaseClient {
  final requests = <_SearchRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/site/settings.json') {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode('{"chat_enabled":true,"chat_search_enabled":true}'),
        ),
        200,
      );
    }
    if (request.url.path == '/directory-columns.json') {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    }
    if (request.url.path == '/session/current.json') {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(
            '{"current_user":{"has_chat_enabled":true,"can_chat":true}}',
          ),
        ),
        200,
      );
    }
    final pending = _SearchRequest(request);
    requests.add(pending);
    return pending.response.future;
  }
}

class _SearchRequest {
  _SearchRequest(this.request) {
    if (request case http.Abortable(:final abortTrigger)) {
      unawaited(
        abortTrigger?.then((_) {
          aborted = true;
          if (!response.isCompleted) {
            response.completeError(http.RequestAbortedException(request.url));
          }
        }),
      );
    }
  }

  final http.BaseRequest request;
  final response = Completer<http.StreamedResponse>();
  bool aborted = false;
  String get term =>
      request.url.queryParameters['q'] ??
      request.url.queryParameters['term'] ??
      '';

  void complete(Map<String, dynamic> body) => response.complete(
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), 200),
  );
}

class _CountingLookupApi extends GlobalSearchApi {
  _CountingLookupApi(DiscourseApi api) : super(transport: api);
  int lookupStarts = 0;

  @override
  Future<List<GlobalSearchFilterChoice>> lookupChoices({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchFilter filter,
    required String term,
    GlobalSearchCapabilities capabilities = const GlobalSearchCapabilities(),
    Future<void>? abortTrigger,
  }) {
    lookupStarts++;
    return super.lookupChoices(
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
      filter: filter,
      term: term,
      capabilities: capabilities,
      abortTrigger: abortTrigger,
    );
  }
}
