import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/shell/shell_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  const site = 'https://example.com';

  testWidgets('debounces valid terms and lets filter syntax bypass length', (
    tester,
  ) async {
    final api = _SearchApi();
    final search = _controller(api)..selectSite(site, minimumLength: 5);
    addTearDown(search.dispose);

    search.setQuery('four');
    await tester.pump(const Duration(seconds: 1));
    expect(api.terms, isEmpty);
    expect(search.phase, SearchSessionPhase.tooShort);

    search.setQuery('  in:title  ');
    await tester.pump(const Duration(milliseconds: 399));
    expect(api.terms, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(api.terms, ['  in:title  ']);
    expect(api.typeFilters, ['exclude_topics']);
  });

  testWidgets('mirrors core facet suggestions before the Enter topic search', (
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

    search.showTopics();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(search.mode, SearchMode.topics);
    expect(api.terms, ['@sam test', '@sam test']);
    expect(api.typeFilters, ['exclude_topics', null]);
    expect(search.sections.map((section) => section.kind), [
      SearchResultKind.topic,
    ]);
  });

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

  testWidgets('keeps only the newest query behind two active searches', (
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

  testWidgets('switching forum clears the session and rejects late work', (
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

const _facetedResults = SearchResults(
  hits: [_facetTopic],
  sections: [
    SearchResultSection(kind: SearchResultKind.topic, results: [_facetTopic]),
    SearchResultSection(
      kind: SearchResultKind.tag,
      results: [SearchTagHit(tagId: 2, name: 'flaky-test')],
    ),
    SearchResultSection(
      kind: SearchResultKind.group,
      results: [SearchGroupHit(groupId: 3, name: 'automation-test')],
    ),
  ],
);

class _SearchApi extends FakeDiscourseApi {
  final List<String> terms = [];
  final List<String?> typeFilters = [];
  final Map<String, Completer<SearchResults>> _answers = {};

  @override
  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    String? apiKey,
    String? clientId,
  }) {
    terms.add(term);
    typeFilters.add(typeFilter);
    return (_answers[term] ??= Completer<SearchResults>()).future;
  }

  void complete(String term, SearchResults results) {
    _answers[term]!.complete(results);
  }
}
