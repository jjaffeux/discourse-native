import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/search_presentation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/global_search_fixtures.dart';

void main() {
  test('opening reads plugin context and seed after canonical publication', () {
    final shell = createGlobalSearchFixtureController();
    addTearDown(shell.dispose);
    final events = <String>[];
    final source = _OpeningSource(events);
    shell.globalSearch.addListener(() {
      events.add('published');
      source.words = 'after';
    });
    SearchPresentation(shell.globalSearch).prepareOpening(source: source);
    expect(events.take(3), ['expression:before', 'route', 'published']);
    expect(events, contains('plugin:after'));
    expect(events.last, 'published');
    expect(shell.globalSearch.query, 'after ');
  });

  test(
    'leaving retains the draft and deferred clearing belongs to that route',
    () {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      final global = shell.globalSearch;
      final owner = SearchPresentation(global);
      const draft = TextEditingValue(
        text: 'design',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
        composing: TextRange(start: 0, end: 6),
      );
      owner.surfaceChanged(true, draft);
      global.setQuery(draft.text);
      final first = Object();
      owner.beginLeaving(first);
      expect(owner.isOpen, isTrue);
      owner.surfaceChanged(false, draft);
      owner.clearSubmittedSearch();
      owner.retireClosedDraft('category:2');
      expect(global.query, draft.text);
      expect(owner.restoredDraft, draft);
      expect(owner.phase, SearchPresentationPhase.leaving);

      owner.finishLeaving();
      expect(global.query, isEmpty);
      global.setQuery('new draft');
      owner.surfaceChanged(true, const TextEditingValue(text: 'new draft'));
      final second = Object();
      owner.beginLeaving(second);
      expect(owner.finishLeaving(surface: first), isFalse);
      expect(owner.phase, SearchPresentationPhase.leaving);
      expect(global.query, 'new draft');
      expect(owner.finishLeaving(surface: second), isTrue);
      expect(global.query, 'new draft');
    },
  );

  test(
    'retained draft restores exact selection only for matching canonical text',
    () {
      final shell = createGlobalSearchFixtureController();
      addTearDown(shell.dispose);
      final owner = SearchPresentation(shell.globalSearch);
      const draft = TextEditingValue(
        text: 'words',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      shell.globalSearch.setQuery('words');
      owner.surfaceChanged(false, draft);
      expect(owner.restoredDraft, draft);
      shell.globalSearch.setQuery('replacement');
      expect(owner.restoredDraft, isNull);
    },
  );

  test('activation keeps the original source, host and account lease', () {
    final lifecycle = SiteLifecycle();
    final host = Object();
    final route = ContentRoute.searchList('design');
    final attempt = SearchResultActivation(
      host: host,
      lease: lifecycle.capture('site'),
      site: 'site',
      sourceRoute: route,
      words: 'design',
      result: const GlobalSearchResult(
        id: 'one',
        scope: GlobalSearchScope.forum,
        title: 'One',
        path: '/t/one/1',
      ),
    );
    bool valid({
      Object? currentHost,
      bool ownsInput = true,
      ContentRoute? currentRoute,
    }) => attempt.canNavigate(
      currentHost: currentHost ?? host,
      contextHost: host,
      sourceOwnsInput: ownsInput,
      currentRoute: currentRoute ?? route,
      searchSite: 'site',
      activeSite: 'site',
    );
    expect(valid(), isTrue);
    expect(valid(currentHost: Object()), isFalse);
    expect(valid(ownsInput: false), isFalse);
    expect(valid(currentRoute: ContentRoute.searchList('other')), isFalse);
    lifecycle.invalidate('site');
    lifecycle.capture('site');
    expect(valid(), isFalse);
  });

  for (final taxonomy in [false, true]) {
    test(
      'delayed words require the exact opened tab and destination ($taxonomy)',
      () {
        final lifecycle = SiteLifecycle();
        final previous = ContentRoute.searchList('before');
        final route = ContentRoute.searchList('after');
        final tab = Object();
        final attempt = SearchResultActivation(
          host: Object(),
          lease: lifecycle.capture('site'),
          site: 'site',
          sourceRoute: previous,
          words: 'design',
          result: GlobalSearchResult(
            id: 'one',
            scope: GlobalSearchScope.forum,
            title: 'One',
            path: '/one',
            destination: route.destination,
            source: taxonomy
                ? const SearchTagHit(tagId: 1, name: 'design')
                : null,
          ),
        );
        String? transfer({
          Object? currentTab,
          bool ownsInput = true,
          ContentRoute? destination,
        }) => attempt.wordsForDestination(
          ownsInput: ownsInput,
          capturedTab: tab,
          currentTab: currentTab ?? tab,
          route: destination ?? route,
          previousRoute: previous,
        );
        expect(transfer(), taxonomy ? '' : 'design');
        expect(transfer(currentTab: Object()), isNull);
        expect(transfer(ownsInput: false), isNull);
        expect(transfer(destination: previous), isNull);
        lifecycle.invalidate('site');
        expect(transfer(), isNull);
      },
    );
  }
}

final class _OpeningSource implements SearchPresentationSource {
  _OpeningSource(this.events);
  final List<String> events;
  String words = 'before';

  @override
  String get expression {
    events.add('expression:$words');
    return words;
  }

  @override
  ContentRoute get route {
    events.add('route');
    return ContentRoute.searchList('before');
  }

  @override
  GlobalSearchContext? get pluginContext {
    events.add('plugin:$words');
    return null;
  }
}
