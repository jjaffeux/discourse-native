import 'dart:async';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/shell/shell_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  const site = 'https://example.com';

  group('query admission and debounce', () {
    testWidgets('waits for valid terms and admits short filter syntax', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site, minimumLength: 5);
      addTearDown(search.dispose);

      search.setQuery('four');
      await tester.pump(const Duration(seconds: 1));
      expect(api.terms, isEmpty);
      expect(search.phase, SearchSessionPhase.tooShort);

      search.setQuery('  before:2020  ');
      await tester.pump(const Duration(milliseconds: 399));
      expect(api.terms, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(api.terms, ['  before:2020  ']);
      expect(api.typeFilters, ['exclude_topics']);
    });

    testWidgets('refuses oversized queries before credentials or API work', (
      tester,
    ) async {
      final api = _SearchApi();
      final credentials = _RecordingCredentials();
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('x' * (DiscourseApi.maximumSearchTermLength + 1));
      await tester.pump(const Duration(seconds: 1));

      expect(search.phase, SearchSessionPhase.refused);
      expect(search.message, 'Searches can be at most 2048 characters.');
      expect(credentials.apiKeySites, isEmpty);
      expect(credentials.clientIdReads, 0);
      expect(api.terms, isEmpty);
    });
  });

  group('search interaction', () {
    testWidgets('shows core facets before switching to topic results', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('@sam test');
      await tester.pump(const Duration(milliseconds: 400));
      api.complete('@sam test', _facetedResults);
      await tester.pump();

      expect(search.mode, SearchMode.facets);
      expect(api.typeFilters, ['exclude_topics']);
      expect(search.sections.map((section) => section.kind), [
        SearchResultKind.tag,
        SearchResultKind.group,
      ]);
      expect(search.topicsActionSelected, isFalse);
      expect(search.selectedResult, isNull);

      expect(search.moveSelection(1), isTrue);
      expect(search.topicsActionSelected, isTrue);
      search.moveSelection(1);
      expect(search.selectedResult, _facetTag);
      search.moveSelection(-1);
      expect(search.topicsActionSelected, isTrue);
      search.moveSelection(-1);
      expect(search.topicsActionSelected, isFalse);
      expect(search.selectedResult, isNull);
      expect(search.moveSelection(-1), isFalse);

      search.showTopics();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(search.mode, SearchMode.topics);
      expect(api.terms, ['@sam test', '@sam test']);
      expect(api.typeFilters, ['exclude_topics', null]);
      expect(search.sections.map((section) => section.kind), [
        SearchResultKind.topic,
      ]);
      expect(search.selectedResult, isNull);
    });

    testWidgets('limits searches to a topic and restores global facets', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      search.requestTopicFocus(42);
      search.setQuery('needle');
      await tester.pump(const Duration(milliseconds: 400));

      expect(search.topicId, 42);
      expect(search.mode, SearchMode.topics);
      expect(api.terms, ['needle']);
      expect(api.typeFilters, [null]);
      expect(api.topicIds, [42]);

      search.requestFocus();
      await tester.pump(const Duration(milliseconds: 400));

      expect(search.topicId, isNull);
      expect(search.mode, SearchMode.facets);
      expect(api.terms, ['needle', 'needle']);
      expect(api.typeFilters, [null, 'exclude_topics']);
      expect(api.topicIds, [42, null]);
    });

    testWidgets('completes trailing modifiers with core assistants', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('look #ra');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(api.terms, isEmpty);
      expect(api.hashtagTerms, ['ra']);
      expect(search.phase, SearchSessionPhase.suggestions);
      expect(search.suggestions.map((item) => item.completion), [
        'look #random',
        'look #random-tag',
      ]);
      expect(search.selectedSuggestion, isNull);

      search.moveSelection(1);
      final category = search.selectedSuggestion!;
      search.acceptSuggestion(category);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(search.query, 'look #random');
      expect(search.mode, SearchMode.topics);
      expect(api.terms, ['look #random']);
      expect(api.typeFilters, [null]);

      search.clear();
      search.setQuery('status:c');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(search.suggestions.map((item) => item.label), ['status:closed']);

      search.clear();
      search.selectSite(site, taggingEnabled: false);
      search.setQuery('#ra');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(api.hashtagOrders.last, ['category']);
      expect(search.suggestions.map((item) => item.kind), [
        SearchSuggestionKind.category,
      ]);
    });

    testWidgets('orders user suggestions like core and omits group rows', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('@team');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(api.userTerms, ['team']);
      expect(search.suggestions.map((item) => item.completion), [
        '@team',
        '@team-support',
      ]);
      expect(search.suggestions.map((item) => item.kind), [
        SearchSuggestionKind.user,
        SearchSuggestionKind.user,
      ]);
      expect(search.suggestions.map((item) => item.label), [
        'team',
        'team-support',
      ]);
    });

    testWidgets(
      'starts unselected and navigates topic results through More without '
      'wrapping',
      (tester) async {
        final api = _SearchApi();
        final search = _controller(api)..selectSite(site);
        addTearDown(search.dispose);

        search.setQuery('query');
        await tester.pump(const Duration(milliseconds: 400));
        api.complete('query', _facetedResults);
        await tester.pump();
        search.showTopics();
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();

        expect(search.selectedResult, isNull);
        expect(search.hasMoreTopics, isTrue);
        search.moveSelection(1);
        expect(search.selectedResult, _facetTopic);
        search.moveSelection(1);
        expect(search.moreActionSelected, isTrue);
        expect(search.moveSelection(1), isFalse);
        expect(search.moreActionSelected, isTrue);
        search.moveSelection(-1);
        expect(search.selectedResult, _facetTopic);
        search.moveSelection(-1);
        expect(search.selectedResult, isNull);
        expect(search.moveSelection(-1), isFalse);
      },
    );

    testWidgets('returns edited topic results to debounced facet mode', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('query');
      await tester.pump(const Duration(milliseconds: 400));
      api.complete('query', _facetedResults);
      await tester.pump();
      search.showTopics();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(search.mode, SearchMode.topics);

      search.setQuery('changed');
      expect(search.mode, SearchMode.facets);
      expect(search.phase, SearchSessionPhase.waiting);
      await tester.pump(const Duration(milliseconds: 399));
      expect(api.terms, isNot(contains('changed')));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(api.terms.last, 'changed');
      expect(api.typeFilters.last, 'exclude_topics');
    });

    testWidgets('credits opened results to their originating search log', (
      tester,
    ) async {
      final api = _SearchApi();
      final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('query');
      await tester.pump(const Duration(milliseconds: 400));
      api.complete(
        'query',
        const SearchResults(
          hits: [_facetTopic],
          sections: [
            SearchResultSection(
              kind: SearchResultKind.topic,
              results: [_facetTopic],
            ),
          ],
          searchLogId: 77,
        ),
      );
      await tester.pump();
      search.showTopics();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      search.recordSelection(_facetTopic);
      await tester.pump();
      expect(api.searchClicks, [
        (searchLogId: 77, resultId: 1, resultKind: SearchResultKind.topic),
      ]);
    });
  });

  group('recent-search lifecycle', () {
    testWidgets('loads, reuses, and clears authenticated searches', (
      tester,
    ) async {
      final api = _SearchApi()..recent = const ['yellow', 'blue'];
      final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);
      final field = Object();
      final unregister = search.registerFocus(field, () {});
      addTearDown(unregister);

      search.activateField(field);
      await tester.pump();
      expect(search.panelOpen, isTrue);
      expect(search.phase, SearchSessionPhase.idle);
      expect(search.recentSearches, ['yellow', 'blue']);
      expect(api.recentSites, [site]);

      search.useRecentSearch('blue');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(search.query, 'blue');
      expect(search.mode, SearchMode.topics);
      expect(api.typeFilters.last, isNull);

      api.complete('blue', _facetedResults);
      await tester.pump();
      search.clearQuery();
      expect(api.recentSites, [site]);
      await search.resetRecentSearches();
      expect(search.recentSearches, isEmpty);
      expect(api.recentResetCount, 1);
    });

    testWidgets('ignores older loads after a newer site request completes', (
      tester,
    ) async {
      const otherSite = 'https://other.example';
      final api = _SearchApi()..gateRecentSearches = true;
      final credentials = FakeApiCredentialReader()
        ..keys[site] = 'first-secret'
        ..keys[otherSite] = 'other-secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);
      final field = Object();
      final unregister = search.registerFocus(field, () {});
      addTearDown(unregister);

      search.activateField(field);
      await tester.pump();
      search.selectSite(otherSite);
      search.activateField(field);
      await tester.pump();
      search.selectSite(site);
      search.activateField(field);
      await tester.pump();

      expect(api.recentSites, [site, otherSite, site]);
      api.completeRecent(2, const ['newest']);
      await tester.pump();
      expect(search.recentSearches, ['newest']);

      api.completeRecent(1, const ['other']);
      api.completeRecent(0, const ['stale']);
      await tester.pump();
      expect(search.recentSearches, ['newest']);
    });

    testWidgets('keeps a completed search when resetting recents fails', (
      tester,
    ) async {
      final reset = Completer<void>();
      final api = _SearchApi()
        ..recent = const ['old']
        ..recentReset = reset;
      final credentials = FakeApiCredentialReader()..keys[site] = 'secret';
      final search = ShellSearchController(
        api: api,
        credentials: credentials,
        lifecycle: SiteLifecycle(),
      )..selectSite(site);
      addTearDown(search.dispose);
      final field = Object();
      final unregister = search.registerFocus(field, () {});
      addTearDown(unregister);

      search.activateField(field);
      await tester.pump();
      final resetOperation = search.resetRecentSearches();
      await tester.pump();
      expect(search.recentSearches, isEmpty);

      search.setQuery('new');
      search.showTopics();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(api.terms, ['new']);
      api.complete('new', _results(2, 'New result'));
      await tester.pump();
      expect(search.recentSearches, ['new']);

      reset.completeError(StateError('offline'), StackTrace.current);
      await resetOperation;
      expect(search.recentSearches, ['new']);
    });
  });

  group('response ordering and site changes', () {
    testWidgets('publishes only the newest result when responses cross', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('first');
      await tester.pump(const Duration(milliseconds: 400));
      search.setQuery('second');
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.terms, ['first', 'second']);

      api.complete('second', _results(2, 'Second result'));
      await tester.pump();
      expect(search.hits.single.postId, 2);

      api.complete('first', _results(1, 'Stale result'));
      await tester.pump();
      expect(search.hits.single.postId, 2);
    });

    testWidgets('retains only the newest queued query behind active searches', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      for (final term in ['first', 'second', 'third', 'fourth']) {
        search.setQuery(term);
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(api.terms, ['first', 'second']);

      api.complete('first', _results(1, 'Old'));
      await tester.pump();
      expect(api.terms, ['first', 'second', 'fourth']);
      expect(api.terms, isNot(contains('third')));
    });

    testWidgets('clears the session on forum switch and rejects late work', (
      tester,
    ) async {
      final api = _SearchApi();
      final search = _controller(api)..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('query');
      await tester.pump(const Duration(milliseconds: 400));
      search.selectSite('https://other.example');

      expect(search.query, isEmpty);
      expect(search.panelOpen, isFalse);
      expect(search.phase, SearchSessionPhase.idle);

      api.complete('query', _results(1, 'Private old result'));
      await tester.pump();
      expect(search.hits, isEmpty);
    });
  });

  group('search failure handling', () {
    test('reports failures while preserving an empty fallback state', () async {
      final diagnostics = await _installDiagnostics('search-failure');
      final api = _SearchApi();
      final search = ShellSearchController(
        api: api,
        credentials: FakeApiCredentialReader(),
        lifecycle: SiteLifecycle(),
        debounceDuration: Duration.zero,
      )..selectSite(site);
      addTearDown(search.dispose);

      search.setQuery('broken');
      await pumpEventQueue();
      api.fail('broken', StateError('offline'));
      await pumpEventQueue();

      expect(search.phase, SearchSessionPhase.failed);
      expect(search.hits, isEmpty);
      expect(search.sections, isEmpty);
      expect(search.results, isEmpty);
      expect(search.message, "Couldn't search example.com.");
      expect(
        diagnostics.events.whereType<ErrorDiagnosticEvent>().single,
        isA<ErrorDiagnosticEvent>()
            .having((event) => event.operation, 'operation', 'search.load')
            .having((event) => event.source, 'source', 'search')
            .having(
              (event) => event.severity,
              'severity',
              DiagnosticSeverity.error,
            )
            .having((event) => event.handled, 'handled', isTrue)
            .having((event) => event.degraded, 'degraded', isTrue),
      );
    });
  });
}

Future<DiagnosticsController> _installDiagnostics(String sessionId) async {
  final diagnostics = await DiagnosticsController.create(
    persistence: MemoryDiagnosticsPersistence(),
    sessionId: sessionId,
  );
  final binding = DiagnosticsSink.install(diagnostics);
  addTearDown(() async {
    binding.close();
    await diagnostics.close();
  });
  return diagnostics;
}

ShellSearchController _controller(_SearchApi api) => ShellSearchController(
  api: api,
  credentials: FakeApiCredentialReader(),
  lifecycle: SiteLifecycle(),
);

SearchResults _results(int id, String title) => SearchResults(
  hits: [
    SearchPostHit(
      postId: id,
      topicId: id * 10,
      postNumber: 2,
      topicTitle: title,
      topicSlug: 'topic-$id',
      username: 'sam',
      excerpt: const SearchExcerpt([SearchExcerptSegment('match')]),
    ),
  ],
);

const _facetTopic = SearchPostHit(
  postId: 1,
  topicId: 10,
  postNumber: 2,
  topicTitle: 'Topic result',
  topicSlug: 'topic-result',
  username: 'sam',
  excerpt: SearchExcerpt([SearchExcerptSegment('test')]),
);

const _facetTag = SearchTagHit(tagId: 2, name: 'flaky-test');
const _facetGroup = SearchGroupHit(groupId: 3, name: 'automation-test');

const _facetedResults = SearchResults(
  hits: [_facetTopic],
  sections: [
    SearchResultSection(
      kind: SearchResultKind.topic,
      results: [_facetTopic],
      hasMore: true,
    ),
    SearchResultSection(kind: SearchResultKind.tag, results: [_facetTag]),
    SearchResultSection(kind: SearchResultKind.group, results: [_facetGroup]),
  ],
);

final class _RecordingCredentials extends FakeApiCredentialReader {
  final List<String> apiKeySites = [];
  int clientIdReads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    apiKeySites.add(siteUrl);
    return super.apiKeyFor(siteUrl);
  }

  @override
  Future<String> clientId() {
    clientIdReads++;
    return super.clientId();
  }
}

class _SearchApi extends FakeDiscourseApi {
  final List<String> terms = [];
  final List<String?> typeFilters = [];
  final List<int?> topicIds = [];
  final Map<String, Completer<SearchResults>> _answers = {};
  final List<String> hashtagTerms = [];
  final List<List<String>> hashtagOrders = [];
  final List<String> userTerms = [];
  List<String> recent = const [];
  int recentResetCount = 0;
  bool gateRecentSearches = false;
  final List<String> recentSites = [];
  final List<Completer<List<String>>> recentAnswers = [];
  Completer<void>? recentReset;

  @override
  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    int? topicId,
    bool searchForId = false,
    String? restrictToArchetype,
    String? apiKey,
    String? clientId,
  }) {
    terms.add(term);
    typeFilters.add(typeFilter);
    topicIds.add(topicId);
    return (_answers[term] ??= Completer<SearchResults>()).future;
  }

  @override
  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
    List<String> order = DiscourseApi.hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async {
    hashtagTerms.add(term);
    hashtagOrders.add(order);
    return const [
      FoundHashtag(
        type: 'category',
        ref: 'random',
        slug: 'random',
        text: 'Random',
        id: 1,
      ),
      FoundHashtag(
        type: 'tag',
        ref: 'random-tag::tag',
        slug: 'random-tag',
        text: 'random-tag',
        id: 2,
      ),
    ];
  }

  @override
  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  }) async {
    userTerms.add(term);
    return const FoundUsersAndGroups(
      users: [
        FoundUser(username: 'team-support'),
        FoundUser(username: 'team'),
      ],
      groups: [FoundGroup(name: 'team-member')],
    );
  }

  @override
  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    recentSites.add(siteUrl);
    if (!gateRecentSearches) return recent;
    final answer = Completer<List<String>>();
    recentAnswers.add(answer);
    return answer.future;
  }

  @override
  Future<void> resetRecentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    recentResetCount++;
    await recentReset?.future;
  }

  void completeRecent(int index, List<String> searches) {
    recentAnswers[index].complete(searches);
  }

  void complete(String term, SearchResults results) {
    _answers[term]!.complete(results);
  }

  void fail(String term, Object error) {
    _answers[term]!.completeError(error, StackTrace.current);
  }
}
