import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/global_search_api.dart';
import 'package:discourse_native/src/shell/global_search_controller.dart';
import 'package:discourse_native/src/shell/global_search_filters.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _site = 'https://example.test';
const _caps = GlobalSearchCapabilities(
  authenticated: true,
  username: 'mira',
  chat: true,
  staff: true,
  admin: true,
  solved: true,
  assign: true,
  poll: true,
  voting: true,
  unlisted: true,
  whispers: true,
);

void main() {
  for (final action in ['none', 'scope', 'recent', 'close']) {
    testWidgets(
      'late chat capabilities respect the opening context after $action',
      (tester) async {
        final gate = Completer<GlobalSearchCapabilities>();
        final api = _EngineApi()..capabilitiesGate = gate;
        final search =
            GlobalSearchController(
              api: api,
              credentials: FakeApiCredentialReader()..keys[_site] = 'key',
              lifecycle: SiteLifecycle(),
            )..configure(
              siteUrl: _site,
              capabilities: const GlobalSearchCapabilities(
                authenticated: true,
                chatEligible: true,
              ),
            );
        addTearDown(search.dispose);
        search.setContext(
          const GlobalSearchContext(
            scope: GlobalSearchScope.chat,
            condition: GlobalSearchCondition(
              filterId: 'chatChannel',
              value: ['12'],
            ),
          ),
        );
        if (action == 'scope') search.setScope(GlobalSearchScope.users);
        if (action == 'recent') search.useRecentSearch('design');
        if (action == 'close') search.clearAllConditions();
        gate.complete(_caps);
        await tester.pump(const Duration(seconds: 1));
        expect(search.scope, switch (action) {
          'scope' => GlobalSearchScope.users,
          'recent' || 'close' => GlobalSearchScope.all,
          _ => GlobalSearchScope.chat,
        });
        expect(
          search.conditions.map((c) => c.text),
          action == 'none' ? ['12'] : <String>[],
        );
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  testWidgets('clearing all filters rejects pending filtered results', (
    tester,
  ) async {
    final api = _EngineApi()..hold = true;
    final search = _controller(api);
    addTearDown(search.dispose);
    search.addCondition(
      const GlobalSearchCondition(filterId: 'author', value: ['sam']),
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(api.requests.single.conditions.single.text, 'sam');

    search.clearAllConditions();
    expect(search.phase, GlobalSearchPhase.idle);
    api.pending.single.complete(_page('Filtered result'));
    await tester.pump(const Duration(milliseconds: 10));
    expect(search.results, isEmpty);
    expect(search.phase, GlobalSearchPhase.idle);
    expect(api.requests, hasLength(1));
  });

  testWidgets(
    'opening context replaces only its own filter and preserves other banks',
    (tester) async {
      final api = _EngineApi();
      final search = _controller(api);
      addTearDown(search.dispose);
      search.addCondition(
        const GlobalSearchCondition(filterId: 'chatAuthor', value: ['mira']),
      );
      search.setQuery('design');
      const first = GlobalSearchContext(
        scope: GlobalSearchScope.chat,
        condition: GlobalSearchCondition(filterId: 'chatChannel', value: ['9']),
        label: 'Design',
      );
      search.setContext(first);
      await tester.pump(const Duration(milliseconds: 10));
      expect(search.scope, GlobalSearchScope.chat);
      expect(api.requests.last.conditions.map((c) => c.text), ['mira', '9']);
      expect(search.choiceLabel('chatChannel', '9'), 'Design');
      search.removeCondition(1);
      search.setScope(GlobalSearchScope.users);
      search.setContext(first);
      expect(search.scope, GlobalSearchScope.chat);
      expect(search.conditions.map((c) => c.text), ['mira', '9']);
      search.setContext(
        const GlobalSearchContext(
          scope: GlobalSearchScope.chat,
          condition: GlobalSearchCondition(
            filterId: 'chatChannel',
            value: ['12'],
          ),
          label: 'david, sam',
        ),
      );
      expect(search.conditions.map((c) => c.text), ['mira', '12']);
      search.setContext(
        const GlobalSearchContext(
          scope: GlobalSearchScope.forum,
          condition: GlobalSearchCondition(
            filterId: 'topicId',
            value: ['1038'],
          ),
        ),
      );
      expect(search.conditions.single.text, '1038');
      expect(
        search.conditionsFor(GlobalSearchScope.chat).single.filterId,
        'chatAuthor',
      );
      search.setContext(
        const GlobalSearchContext(scope: GlobalSearchScope.forum),
      );
      expect(search.conditions, isEmpty);
      expect(search.query, 'design');
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  test('channel IDs scope chat requests without relying on a slug', () async {
    final transport = _Transport();
    final api = GlobalSearchApi(transport: transport);
    await api.search(
      siteUrl: _site,
      apiKey: 'key',
      request: const GlobalSearchRequest(
        scope: GlobalSearchScope.chat,
        query: 'needle',
        capabilities: _caps,
        conditions: [
          GlobalSearchCondition(filterId: 'chatChannel', value: ['12']),
        ],
      ),
    );
    expect(transport.paths.single.queryParameters, {
      'query': 'needle',
      'sort': 'relevance',
      'offset': '0',
      'limit': '20',
      'channel_id': '12',
    });
  });

  test(
    'All reports a forum timeout while retaining successful chat results',
    () async {
      final transport = _Transport()
        ..failures['/search/query.json'] = SiteLookupException(
          SiteLookupFailure.unreachable,
          _site,
          cause: TimeoutException('private request details'),
        )
        ..responses['/chat/api/search.json'] = {
          'messages': [
            {
              'id': 9,
              'chat_channel_id': 3,
              'channel': {'id': 3, 'slug': 'design'},
              'user': {'username': 'mira'},
              'message': 'A matching chat message',
            },
          ],
        };
      final api = GlobalSearchApi(transport: transport);
      const request = GlobalSearchRequest(
        scope: GlobalSearchScope.all,
        query: 'test',
        capabilities: _caps,
      );
      final page = await api.search(
        siteUrl: _site,
        apiKey: 'key',
        request: request,
      );
      expect(
        page.sections.first.error,
        'The search timed out. Please try again.',
      );
      expect(page.sections.last.results.single.messageId, 9);

      transport.failures.clear();
      transport.responses['/search/query.json'] = {
        'posts': [
          {'id': 1, 'topic_id': 2, 'post_number': 1, 'blurb': 'A test result'},
        ],
        'topics': [
          {'id': 2, 'title': 'Test result', 'slug': 'test-result'},
        ],
      };
      final retry = await api.search(
        siteUrl: _site,
        apiKey: 'key',
        request: request,
      );
      expect(retry.sections.where((section) => section.error != null), isEmpty);
      expect(retry.sections.first.results.single.title, 'Test result');
      expect(retry.sections.last.results.single.messageId, 9);
    },
  );

  testWidgets(
    'dedicated search reports a timeout and retry replaces the error',
    (tester) async {
      final api = _EngineApi()..hold = true;
      final controller = _controller(api)..setScope(GlobalSearchScope.forum);
      addTearDown(controller.dispose);
      controller.setQuery('test');
      await tester.pump(const Duration(seconds: 1));
      api.pending.single.completeError(
        SiteLookupException(
          SiteLookupFailure.unreachable,
          _site,
          cause: TimeoutException('private request details'),
        ),
      );
      await tester.pump();
      expect(controller.phase, GlobalSearchPhase.failed);
      expect(controller.error, 'The search timed out. Please try again.');
      controller.retry();
      await tester.pump();
      api.pending.last.complete(_page('Recovered result'));
      await tester.pump();
      expect(controller.error, isNull);
      expect(controller.results.single.title, 'Recovered result');
    },
  );

  test('busy and rate-limited searches have specific recovery messages', () {
    expect(
      GlobalSearchApi.failureMessage(
        const SiteLookupException(
          SiteLookupFailure.unreachable,
          _site,
          statusCode: 409,
        ),
      ),
      'The forum is busy. Please try again.',
    );
    expect(
      GlobalSearchApi.failureMessage(
        const SiteLookupException(
          SiteLookupFailure.unreachable,
          _site,
          statusCode: 429,
        ),
      ),
      'Too many searches. Wait a moment before trying again.',
    );
    expect(
      GlobalSearchApi.failureMessage(StateError('private request details')),
      'Search could not load. Please try again.',
    );
  });

  test('forum expression preserves date ranges, tag conditions and ordering', () {
    final parsed = parseGlobalSearchExpression(
      'design after:2026-01-01 before:2026-09-01 tags:ux+search -tags:noise created:@me order:likes',
      GlobalSearchScope.forum,
      _caps,
    );
    expect(parsed.query, 'design');
    expect(parsed.order, 'likes');
    expect(
      parsed.conditions.map(
        (c) => globalSearchConditionToken(c, username: 'mira'),
      ),
      [
        'after:2026-01-01',
        'before:2026-09-01',
        'tags:ux+search',
        '-tags:noise',
        'created:@mira',
      ],
    );
  });

  test(
    'invalid values and disabled operator capabilities fail before transport',
    () {
      expect(
        validateGlobalSearchCondition(
          const GlobalSearchCondition(
            filterId: 'postDate',
            operator: 'after',
            value: ['2026-02-30'],
          ),
          _caps,
        ),
        isNotNull,
      );
      expect(
        validateGlobalSearchCondition(
          const GlobalSearchCondition(
            filterId: 'files',
            operator: 'any',
            value: ['pdf in:personal'],
          ),
          _caps,
        ),
        isNotNull,
      );
      expect(
        () => parseGlobalSearchExpression(
          'status:solved',
          GlobalSearchScope.all,
          const GlobalSearchCapabilities(),
        ),
        throwsFormatException,
      );
      expect(
        () => parseGlobalSearchExpression(
          'in:all-pms',
          GlobalSearchScope.forum,
          const GlobalSearchCapabilities(),
        ),
        throwsFormatException,
      );
    },
  );

  test('chat text does not use forum single-letter shortcuts', () {
    final parsed = parseGlobalSearchExpression(
      'l f t',
      GlobalSearchScope.chat,
      _caps,
    );
    expect(parsed.query, 'l f t');
    expect(parsed.order, isNull);
    expect(parsed.conditions, isEmpty);
  });

  testWidgets(
    'All has no hidden bank filters; date range edits affect only one chip',
    (tester) async {
      final api = _EngineApi();
      final controller = _controller(api);
      addTearDown(controller.dispose);
      controller.addCondition(
        const GlobalSearchCondition(
          filterId: 'postDate',
          operator: 'after',
          value: ['2026-01-01'],
        ),
      );
      controller.addCondition(
        const GlobalSearchCondition(
          filterId: 'postDate',
          operator: 'before',
          value: ['2026-09-01'],
        ),
      );
      expect(controller.scope, GlobalSearchScope.forum);
      controller.updateCondition(
        0,
        const GlobalSearchCondition(
          filterId: 'postDate',
          operator: 'after',
          value: ['2026-02-01'],
        ),
      );
      expect(controller.conditions.map((c) => c.text), [
        '2026-02-01',
        '2026-09-01',
      ]);
      controller.setQuery('design');
      controller.setScope(GlobalSearchScope.all);
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests.single.conditions, isEmpty);
      controller.setScope(GlobalSearchScope.forum);
      expect(controller.conditions.length, 2);
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'only newest queued query can publish; stale failures are ignored',
    (tester) async {
      final api = _EngineApi()..hold = true;
      final controller = _controller(api);
      addTearDown(controller.dispose);
      controller.setQuery('first');
      await tester.pump(const Duration(seconds: 1));
      controller.setQuery('second');
      await tester.pump(const Duration(seconds: 1));
      controller.setQuery('third');
      await tester.pump(const Duration(seconds: 1));
      controller.setQuery('newest');
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests.map((r) => r.query), ['first', 'second']);
      api.pending[0].completeError(StateError('old network failure'));
      await tester.pump();
      expect(api.requests.map((r) => r.query), ['first', 'second', 'newest']);
      api.pending[2].complete(_page('newest'));
      await tester.pump();
      api.pending[1].complete(_page('second'));
      await tester.pump();
      expect(controller.results.single.title, 'newest');
      expect(controller.error, isNull);
    },
  );

  testWidgets(
    'account invalidation frees the new session from old in-flight slots',
    (tester) async {
      final api = _EngineApi()..hold = true;
      final lifecycle = SiteLifecycle();
      final controller = _controller(api, lifecycle: lifecycle);
      addTearDown(controller.dispose);
      controller.setQuery('old one');
      await tester.pump(const Duration(seconds: 1));
      controller.setQuery('old two');
      await tester.pump(const Duration(seconds: 1));
      lifecycle.invalidate(_site);
      controller.configure(siteUrl: _site, capabilities: _caps);
      expect(controller.query, isEmpty);
      controller.setQuery('new account');
      await tester.pump(const Duration(seconds: 1));
      expect(api.requests.last.query, 'new account');
      expect(api.requests.length, 3);
      api.pending[2].complete(_page('new account'));
      api.pending[0].complete(_page('old one'));
      api.pending[1].complete(_page('old two'));
      await tester.pump();
      expect(controller.results.single.title, 'new account');
    },
  );

  testWidgets(
    'pagination preserves prior results and deduplicates overlapping pages',
    (tester) async {
      final api = _EngineApi()..hold = true;
      final controller = _controller(api)
        ..setScope(GlobalSearchScope.forum)
        ..setQuery('design');
      addTearDown(controller.dispose);
      await tester.pump(const Duration(seconds: 1));
      api.pending[0].complete(_page('first', hasMore: true));
      await tester.pump();
      controller.loadMore();
      await tester.pump();
      expect(api.requests[1].page, 1);
      expect(api.requests[1].offset, 1);
      expect(controller.results.single.title, 'first');
      api.pending[1].complete(_page('first'));
      await tester.pump();
      expect(controller.results.length, 1);
      expect(controller.hasMore, isFalse);
    },
  );

  testWidgets(
    'directory singleton filters replace their parameter and recent restores scope',
    (tester) async {
      final api = _EngineApi();
      final controller = _controller(api);
      addTearDown(controller.dispose);
      controller.addCondition(
        const GlobalSearchCondition(filterId: 'userGroup', value: ['design']),
      );
      controller.addCondition(
        const GlobalSearchCondition(filterId: 'userGroup', value: ['team']),
      );
      expect(controller.conditions.single.text, 'team');
      controller.setQuery('mira');
      controller.submit();
      final recent = controller.recentSearches.single;
      expect(recent, 'mira group=team');
      controller.setScope(GlobalSearchScope.groups);
      controller.setQuery('support');
      controller.useRecentSearch(recent);
      expect(controller.scope, GlobalSearchScope.users);
      expect(controller.query, 'mira');
      expect(controller.conditions.single.text, 'team');
      await tester.pump();
    },
  );

  test(
    'lookup labels are scoped to site and account and ignore stale responses',
    () async {
      final api = _EngineApi()
        ..lookupValues = const [
          GlobalSearchFilterChoice(value: '3', label: 'Design / Support'),
        ];
      final lifecycle = SiteLifecycle();
      final search = _controller(api, lifecycle: lifecycle);
      addTearDown(search.dispose);
      final filter = globalSearchFilter('category')!;
      await search.lookupChoices(filter, 'support');
      expect(search.choiceLabel('category', '3'), 'Design / Support');
      search.configure(siteUrl: 'https://other.test', capabilities: _caps);
      expect(search.choiceLabel('category', '3'), isNull);
      await search.lookupChoices(filter, 'support');
      expect(search.choiceLabel('category', '3'), 'Design / Support');
      lifecycle.invalidate('https://other.test');
      search.configure(siteUrl: 'https://other.test', capabilities: _caps);
      expect(search.choiceLabel('category', '3'), isNull);
      api.lookupGate = Completer<List<GlobalSearchFilterChoice>>();
      api.lookupStarted = Completer<void>();
      final pending = search.lookupChoices(filter, 'support');
      await api.lookupStarted!.future;
      search.configure(siteUrl: _site, capabilities: _caps);
      api.lookupGate!.complete(api.lookupValues);
      expect(await pending, isEmpty);
      expect(search.choiceLabel('category', '3'), isNull);
    },
  );

  test(
    'applying a draft restores evicted category names and artwork',
    () async {
      const selected = GlobalSearchFilterChoice(
        value: '1',
        label: 'Engineering / Support',
        parentLabel: 'Engineering',
        category: TopicCategory(id: 1, name: 'Support', color: '0088CC'),
      );
      final api = _EngineApi()..categoryValues = const [selected];
      final search = _controller(api);
      addTearDown(search.dispose);
      await search.lookupCategoryChoices('Support');
      expect(search.choice('category', '1'), same(selected));

      api.categoryValues = [
        for (var id = 2; id <= 514; id++)
          GlobalSearchFilterChoice(value: '$id', label: 'Category $id'),
      ];
      await search.lookupCategoryChoices('');
      expect(search.choice('category', '1'), isNull);

      search.rememberCategorySelection([selected]);
      search.addCondition(
        const GlobalSearchCondition(
          filterId: 'category',
          operator: 'any',
          value: ['1'],
        ),
      );
      await search.lookupCategoryChoices('');
      expect(search.choiceLabel('category', '1'), 'Engineering / Support');
      expect(search.choice('category', '1')?.category, same(selected.category));
      expect(search.choice('category', '1')?.parentLabel, 'Engineering');
    },
  );

  test('category pages cannot cross an invalidated account session', () async {
    const selected = GlobalSearchFilterChoice(value: '1', label: 'Old account');
    final api = _EngineApi()..categoryValues = const [selected];
    final lifecycle = SiteLifecycle();
    final search = _controller(api, lifecycle: lifecycle);
    addTearDown(search.dispose);
    await search.lookupCategoryChoices('');
    final oldSession = search.categoryLookupSession;
    api.categoryGate = Completer<GlobalSearchCategoryPage>();
    api.categoryStarted = Completer<void>();
    final pending = search.lookupCategoryChoices('', page: 2);
    await api.categoryStarted!.future;
    lifecycle.invalidate(_site);
    search.configure(siteUrl: _site, capabilities: _caps);
    expect(search.categoryLookupSession, isNot(same(oldSession)));
    expect(search.choice('category', '1'), isNull);

    api.categoryGate!.complete(
      const GlobalSearchCategoryPage(choices: [selected], total: 1),
    );
    expect((await pending).choices, isEmpty);
    expect(search.choice('category', '1'), isNull);
  });

  for (final historicalQuery in ['design category:ux', 'design']) {
    testWidgets(
      'server history $historicalQuery replaces retained forum conditions',
      (tester) async {
        final api = _EngineApi();
        final controller = _controller(api);
        addTearDown(controller.dispose);
        controller.addCondition(
          const GlobalSearchCondition(filterId: 'author', value: ['alice']),
        );
        controller.setOrder('latest');
        controller.addCondition(
          const GlobalSearchCondition(filterId: 'userGroup', value: ['team']),
        );
        controller.useRecentSearch(historicalQuery);
        await tester.pump();
        final request = api.requests.single;
        expect(globalSearchTerm(request), historicalQuery);
        expect(request.order, 'relevance');
        expect(
          controller
              .conditionsFor(GlobalSearchScope.forum)
              .map((c) => c.filterId),
          historicalQuery.contains('category:') ? ['category'] : isEmpty,
        );
        expect(
          controller.conditionsFor(GlobalSearchScope.users).single.text,
          'team',
        );
      },
    );
  }

  test(
    'public category choices use distinct IDs and parent labels and find entries past 100',
    () async {
      final transport = _Transport()
        ..response = {
          'categories': [
            {'id': 1, 'name': 'Design', 'slug': 'design'},
            {'id': 2, 'name': 'Engineering', 'slug': 'engineering'},
            {
              'id': 3,
              'name': 'Support',
              'slug': 'support',
              'parent_category_id': 1,
            },
            {
              'id': 4,
              'name': 'Support',
              'slug': 'support',
              'parent_category_id': 2,
            },
            for (var id = 5; id <= 120; id++)
              {'id': id, 'name': 'Category $id', 'slug': 'category-$id'},
            {
              'id': 500,
              'name': 'Far beyond',
              'slug': 'late-entry',
              'parent_category_id': 2,
            },
          ],
        };
      final api = GlobalSearchApi(transport: transport),
          filter = globalSearchFilter('category')!;
      final support = await api.lookupChoices(
        siteUrl: _site,
        apiKey: null,
        filter: filter,
        term: 'support',
      );
      expect(support.map((c) => (c.value, c.label)), [
        ('3', 'Design / Support'),
        ('4', 'Engineering / Support'),
      ]);
      expect(
        globalSearchConditionToken(
          GlobalSearchCondition(
            filterId: 'category',
            operator: 'exactCategory',
            value: [support.last.value],
          ),
        ),
        'category:=4',
      );
      final late = await api.lookupChoices(
        siteUrl: _site,
        apiKey: null,
        filter: filter,
        term: 'far beyond',
      );
      expect(late.single.value, '500');
      expect(late.single.label, 'Engineering / Far beyond');
      final all = await api.lookupCategoryChoices(
        siteUrl: _site,
        apiKey: null,
        term: '',
      );
      expect(all.choices.length, 121);
      expect(all.hasMore, isFalse);
    },
  );

  test(
    'anonymous lazy category discovery queries and pages the complete taxonomy',
    () async {
      final requests = <http.Request>[];
      final transport = DiscourseApi(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/site.json') {
            return http.Response(
              '{"lazy_load_categories":true,"categories":[]}',
              200,
            );
          }
          expect(request.method, 'POST');
          expect(request.url.path, '/categories/search.json');
          expect(request.headers['user-api-key'], isNull);
          expect(request.headers['user-api-client-id'], isNull);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['term'], 'Support');
          expect(body['include_subcategories'], isTrue);
          final secondPage = body['page'] == 2;
          return http.Response(
            jsonEncode({
              'categories_count': 26,
              'categories': [
                for (
                  var id = secondPage ? 26 : 1;
                  id <= (secondPage ? 26 : 25);
                  id++
                )
                  {'id': id, 'name': 'Support $id'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(transport.close);
      final api = GlobalSearchApi(transport: transport);
      final first = await api.lookupCategoryChoices(
        siteUrl: _site,
        apiKey: null,
        clientId: 'client',
        term: 'Support',
      );
      final second = await api.lookupCategoryChoices(
        siteUrl: _site,
        apiKey: null,
        term: 'Support',
        page: 2,
      );
      expect(first.choices.length, 25);
      expect(first.hasMore, isTrue);
      expect(first.total, 26);
      expect(second.choices.single.value, '26');
      expect(second.hasMore, isFalse);
      expect(requests, hasLength(2));
      expect(requests.every((request) => request.url.query.isEmpty), isTrue);
    },
  );

  test(
    'legacy anonymous transport does not treat a lazy preload as complete',
    () async {
      final transport = _Transport()
        ..response = {
          'lazy_load_categories': true,
          'categories': <Map<String, dynamic>>[],
        };
      await expectLater(
        GlobalSearchApi(
          transport: transport,
        ).lookupCategoryChoices(siteUrl: _site, apiKey: null, term: ''),
        throwsFormatException,
      );
    },
  );

  test(
    'category discovery pages server matches and keeps ancestor artwork',
    () async {
      final transport = _Transport()
        ..categoryResponses = {
          1: {
            'categories_count': 26,
            'categories': [
              for (var id = 1; id <= 25; id++)
                {'id': id, 'name': 'Category $id'},
            ],
          },
          2: {
            'categories_count': 26,
            'ancestors': [
              {'id': 77, 'name': 'Engineering'},
            ],
            'categories': [
              {
                'id': 500,
                'name': 'Support',
                'parent_category_id': 77,
                'color': '0088CC',
                'style_type': 'icon',
                'icon': 'folder',
                'read_restricted': true,
              },
            ],
          },
        };
      final api = GlobalSearchApi(transport: transport);
      final first = await api.lookupCategoryChoices(
        siteUrl: _site,
        apiKey: 'key',
        term: 'support',
      );
      final second = await api.lookupCategoryChoices(
        siteUrl: _site,
        apiKey: 'key',
        term: 'support',
        page: 2,
      );
      expect(first.hasMore, isTrue);
      expect(first.total, 26);
      expect(second.hasMore, isFalse);
      expect(second.choices.single.label, 'Engineering / Support');
      expect(second.choices.single.parentLabel, 'Engineering');
      expect(second.choices.single.category!.color, '0088CC');
      expect(second.choices.single.category!.readRestricted, isTrue);
      expect(transport.paths, isEmpty);
      expect(transport.categorySearchRequests.map((body) => body['page']), [
        1,
        2,
      ]);
      expect(transport.categorySearchRequests.last, {
        'term': 'support',
        'page': 2,
        'limit': 25,
        'include_uncategorized': true,
        'include_subcategories': true,
        'include_ancestors': true,
      });
    },
  );

  test('an empty category page cannot hide remaining server matches', () async {
    final transport = _Transport()
      ..categoryResponses = {
        2: {'categories_count': 26, 'categories': <Object>[]},
      };
    await expectLater(
      GlobalSearchApi(
        transport: transport,
      ).lookupCategoryChoices(siteUrl: _site, apiKey: 'key', term: '', page: 2),
      throwsFormatException,
    );
  });

  test(
    'tag choices serialize the canonical name rather than a differing slug',
    () async {
      final transport = _Transport()
        ..response = {
          'results': [
            {'id': 9, 'name': 'accessibility', 'slug': 'a11y-discussions'},
          ],
        };
      final choices = await GlobalSearchApi(transport: transport).lookupChoices(
        siteUrl: _site,
        apiKey: 'key',
        filter: globalSearchFilter('tags')!,
        term: 'access',
      );
      expect(choices.single.value, 'accessibility');
      expect(
        globalSearchConditionToken(
          GlobalSearchCondition(
            filterId: 'tags',
            operator: 'any',
            value: [choices.single.value],
          ),
        ),
        'tags:accessibility',
      );
    },
  );

  for (final filterId in ['userGroup', 'userName']) {
    testWidgets(
      'editing $filterId exclusion into singleton removes conflicting chip',
      (tester) async {
        final api = _EngineApi();
        final controller = _controller(api);
        addTearDown(controller.dispose);
        controller.addCondition(
          GlobalSearchCondition(filterId: filterId, value: const ['design']),
        );
        controller.addCondition(
          GlobalSearchCondition(
            filterId: filterId,
            operator: 'excludes',
            value: const ['staff'],
          ),
        );
        controller.addCondition(
          GlobalSearchCondition(
            filterId: filterId,
            operator: 'excludes',
            value: const ['admins'],
          ),
        );
        controller.updateCondition(
          1,
          GlobalSearchCondition(filterId: filterId, value: const ['staff']),
        );
        expect(controller.conditions.map((c) => (c.operator, c.text)), [
          ('is', 'staff'),
          ('excludes', 'admins'),
        ]);
        await tester.pump(const Duration(seconds: 1));
        final transport = _Transport();
        await GlobalSearchApi(
          transport: transport,
        ).search(siteUrl: _site, apiKey: 'key', request: api.requests.single);
        final key = filterId == 'userGroup' ? 'group' : 'username';
        final exclusionKey = filterId == 'userGroup'
            ? 'exclude_groups'
            : 'exclude_usernames';
        expect(transport.paths.single.queryParameters[key], 'staff');
        expect(transport.paths.single.queryParameters[exclusionKey], 'admins');
        // The reverse edit keeps both independent exclusions visible and active.
        controller.updateCondition(
          0,
          GlobalSearchCondition(
            filterId: filterId,
            operator: 'excludes',
            value: const ['mods'],
          ),
        );
        expect(controller.conditions.map((c) => (c.operator, c.text)), [
          ('excludes', 'mods'),
          ('excludes', 'admins'),
        ]);
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  test(
    'chat thread results retain thread context in the native navigation path',
    () async {
      final transport = _Transport()
        ..response = {
          'messages': [
            for (final row in [
              (id: 11, thread: 42),
              (id: 12, thread: null),
              (id: 13, thread: 0),
              (id: 14, thread: -1),
            ])
              {
                'id': row.id,
                'chat_channel_id': 7,
                'thread_id': row.thread,
                'message': 'Design review',
                'channel': {'id': 7, 'slug': 'design'},
                'user': {'username': 'mira'},
              },
          ],
        };
      final page = await GlobalSearchApi(transport: transport).search(
        siteUrl: _site,
        apiKey: 'key',
        request: const GlobalSearchRequest(
          scope: GlobalSearchScope.chat,
          query: 'design',
          capabilities: _caps,
        ),
      );
      expect(page.results.map((r) => r.path), [
        '/chat/c/design/7/t/42/11',
        '/chat/c/design/7/12',
        '/chat/c/design/7/13',
        '/chat/c/design/7/14',
      ]);
      expect(page.results.map((r) => r.threadId), [42, null, null, null]);
      expect(page.results.map((r) => r.messageId), [11, 12, 13, 14]);
    },
  );

  test(
    'wire directory query uses presence-only asc and metadata pagination',
    () async {
      final transport = _Transport()
        ..response = {
          'directory_items': [
            {
              'likes_received': 5,
              'user': {'id': 7, 'username': 'mira'},
            },
          ],
          'meta': {
            'total_rows_directory_items': 2,
            'load_more_directory_items': '/directory_items.json?page=1',
          },
        };
      final api = GlobalSearchApi(transport: transport);
      final page = await api.search(
        siteUrl: _site,
        apiKey: 'key',
        request: const GlobalSearchRequest(
          scope: GlobalSearchScope.users,
          query: 'mi',
          capabilities: _caps,
          order: 'username',
          conditions: [
            GlobalSearchCondition(
              filterId: 'userGroup',
              operator: 'excludes',
              value: ['team', 'staff'],
            ),
            GlobalSearchCondition(
              filterId: 'userName',
              operator: 'excludes',
              value: ['system', 'discobot'],
            ),
            GlobalSearchCondition(filterId: 'userPeriod', value: ['weekly']),
          ],
        ),
      );
      expect(transport.paths.single.path, '/directory_items.json');
      expect(transport.paths.single.queryParameters, {
        'name': 'mi',
        'order': 'username',
        'page': '0',
        'period': 'weekly',
        'exclude_groups': 'team|staff',
        'exclude_usernames': 'system,discobot',
      });
      expect(page.hasMore, isTrue);
      expect(page.results.single.username, 'mira');
    },
  );

  test(
    'forum wire query preserves exact category, date range and page one',
    () async {
      final transport = _Transport();
      await GlobalSearchApi(transport: transport).search(
        siteUrl: _site,
        apiKey: null,
        request: const GlobalSearchRequest(
          scope: GlobalSearchScope.forum,
          query: 'design',
          capabilities: _caps,
          order: 'oldest_topic',
          conditions: [
            GlobalSearchCondition(
              filterId: 'category',
              operator: 'exactCategory',
              value: ['ux', 'support'],
            ),
            GlobalSearchCondition(
              filterId: 'postDate',
              operator: 'after',
              value: ['2026-01-01'],
            ),
            GlobalSearchCondition(
              filterId: 'postDate',
              operator: 'before',
              value: ['2026-09-01'],
            ),
          ],
        ),
      );
      expect(transport.paths.single.path, '/search.json');
      expect(transport.paths.single.queryParameters, {
        'q':
            'design category:=ux,=support after:2026-01-01 before:2026-09-01 order:oldest_topic',
        'page': '1',
      });
    },
  );

  test(
    'chat requires actual terms and uses query, offset and exclude_threads',
    () async {
      final transport = _Transport();
      final api = GlobalSearchApi(transport: transport);
      const threads = GlobalSearchCondition(
        filterId: 'chatThreads',
        value: ['exclude'],
      );
      await api.search(
        siteUrl: _site,
        apiKey: 'key',
        request: const GlobalSearchRequest(
          scope: GlobalSearchScope.chat,
          query: '',
          capabilities: _caps,
          conditions: [threads],
        ),
      );
      expect(transport.paths, isEmpty);
      await api.search(
        siteUrl: _site,
        apiKey: 'key',
        request: const GlobalSearchRequest(
          scope: GlobalSearchScope.chat,
          query: 'design',
          capabilities: _caps,
          order: 'latest',
          offset: 20,
          conditions: [
            threads,
            GlobalSearchCondition(filterId: 'chatAuthor', value: ['mira']),
            GlobalSearchCondition(filterId: 'chatChannel', value: ['design']),
          ],
        ),
      );
      expect(transport.paths.single.queryParameters, {
        'query': 'design @mira #design',
        'sort': 'latest',
        'offset': '20',
        'limit': '20',
        'exclude_threads': 'true',
      });
    },
  );

  test(
    'chat capability fails closed when raw session omits enabled preference',
    () async {
      final transport = _Transport()
        ..responses = {
          '/site/settings.json': {
            'chat_enabled': true,
            'chat_search_enabled': true,
          },
          '/session/current.json': {
            'current_user': {'can_chat': true},
          },
        };
      final api = GlobalSearchApi(transport: transport);
      var caps = await api.capabilities(
        siteUrl: _site,
        apiKey: 'key',
        base: const GlobalSearchCapabilities(
          authenticated: true,
          chatEligible: true,
        ),
      );
      expect(caps.chat, isFalse);
      transport.responses['/session/current.json'] = {
        'current_user': {'can_chat': true, 'has_chat_enabled': true},
      };
      caps = await api.capabilities(
        siteUrl: _site,
        apiKey: 'key',
        base: const GlobalSearchCapabilities(
          authenticated: true,
          chatEligible: true,
        ),
      );
      expect(caps.chat, isTrue);
    },
  );
}

GlobalSearchController _controller(
  _EngineApi api, {
  SiteLifecycle? lifecycle,
}) => GlobalSearchController(
  api: api,
  credentials: FakeApiCredentialReader()..keys[_site] = 'key',
  lifecycle: lifecycle ?? SiteLifecycle(),
  debounceDuration: const Duration(milliseconds: 1),
)..configure(siteUrl: _site, capabilities: _caps);

GlobalSearchPage _page(String title, {bool hasMore = false}) =>
    GlobalSearchPage(
      hasMore: hasMore,
      consumedCount: 1,
      sections: [
        GlobalSearchSection(
          scope: GlobalSearchScope.forum,
          hasMore: hasMore,
          results: [
            GlobalSearchResult(
              id: title,
              scope: GlobalSearchScope.forum,
              title: title,
              path: '/t/$title/1',
            ),
          ],
        ),
      ],
    );

class _EngineApi extends GlobalSearchApi {
  _EngineApi() : super(transport: FakeDiscourseApi());
  bool hold = false;
  List<GlobalSearchFilterChoice> lookupValues = const [];
  Completer<List<GlobalSearchFilterChoice>>? lookupGate;
  Completer<void>? lookupStarted;
  List<GlobalSearchFilterChoice> categoryValues = const [];
  Completer<GlobalSearchCategoryPage>? categoryGate;
  Completer<void>? categoryStarted;

  @override
  Future<GlobalSearchCategoryPage> lookupCategoryChoices({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required String term,
    int page = 1,
  }) async {
    if (categoryStarted?.isCompleted == false) categoryStarted!.complete();
    return categoryGate?.future ??
        GlobalSearchCategoryPage(choices: categoryValues);
  }

  @override
  Future<List<GlobalSearchFilterChoice>> lookupChoices({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchFilter filter,
    required String term,
  }) async {
    if (lookupStarted?.isCompleted == false) lookupStarted!.complete();
    return lookupGate?.future ?? lookupValues;
  }

  final requests = <GlobalSearchRequest>[];
  Completer<GlobalSearchCapabilities>? capabilitiesGate;
  final pending = <Completer<GlobalSearchPage>>[];
  @override
  Future<GlobalSearchCapabilities> capabilities({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchCapabilities base,
  }) async => capabilitiesGate?.future ?? base;
  @override
  Future<GlobalSearchPage> search({
    required String siteUrl,
    required String? apiKey,
    String? clientId,
    required GlobalSearchRequest request,
  }) async {
    requests.add(request);
    if (!hold) return const GlobalSearchPage();
    final completer = Completer<GlobalSearchPage>();
    pending.add(completer);
    return completer.future;
  }
}

class _Transport extends FakeDiscourseApi {
  Map<int, Map<String, dynamic>> categoryResponses = {};
  final categorySearchRequests = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (path == '/categories/search.json') {
      expect(method, 'POST');
      categorySearchRequests.add(body);
      return categoryResponses[body['page']] ?? {};
    }
    return super.pluginWriteJson(
      siteUrl: siteUrl,
      path: path,
      method: method,
      apiKey: apiKey,
      body: body,
      clientId: clientId,
    );
  }

  final paths = <Uri>[];
  final failures = <String, Object>{};
  Map<String, dynamic> response = {};
  Map<String, Map<String, dynamic>> responses = {};
  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    paths.add(uri);
    if (failures[uri.path] case final error?) throw error;
    return responses[uri.path] ?? response;
  }
}
