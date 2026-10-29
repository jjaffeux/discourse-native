import 'package:flutter/services.dart';

import '../data/site_lifecycle.dart';
import '../models/content_route.dart';
import '../models/search_results.dart';
import 'content_page_contract.dart';
import 'global_search_controller.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';
import 'shell_search_controller.dart';

enum SearchPresentationPhase { closed, open, leaving }

abstract interface class SearchPresentationSource {
  String get expression;
  ContentRoute? get route;
  GlobalSearchContext? get pluginContext;
}

/// Owns the search surface lifetime while content stays in the search controller.
final class SearchPresentation {
  SearchPresentation(this.global);

  GlobalSearchController global;
  SearchPresentationPhase _phase = SearchPresentationPhase.closed;
  bool _expandedWhileLeaving = false;
  Object? _leaving;
  bool _clearWhenLeft = false;
  bool suppressFocus = false;
  TextEditingValue? _draft;
  String? _openingExpression;
  String? selectedResultId;
  Object? _selectedNavigationIdentity;

  SearchPresentationPhase get phase => _phase;
  bool get isLeaving => _phase == SearchPresentationPhase.leaving;
  bool get isOpen =>
      _phase == SearchPresentationPhase.open ||
      isLeaving && _expandedWhileLeaving;

  void beginLeaving(Object surface) {
    _expandedWhileLeaving = isOpen;
    _leaving = surface;
    _phase = SearchPresentationPhase.leaving;
  }

  void surfaceChanged(bool open, TextEditingValue editing) {
    if (!open) _draft = editing;
    suppressFocus = true;
    if (isLeaving && !open) {
      _expandedWhileLeaving = false;
    } else {
      _phase = open
          ? SearchPresentationPhase.open
          : SearchPresentationPhase.closed;
    }
  }

  TextEditingValue? get restoredDraft =>
      _draft?.text == global.query ? _draft : null;

  void clearSubmittedSearch() {
    if (isLeaving) {
      _clearWhenLeft = true;
      return;
    }
    global.setQuery('');
    global.clearAllConditions();
  }

  bool finishLeaving({Object? surface}) {
    if (surface != null && !identical(_leaving, surface)) return false;
    _leaving = null;
    _phase = _expandedWhileLeaving
        ? SearchPresentationPhase.open
        : SearchPresentationPhase.closed;
    if (_clearWhenLeft) {
      _clearWhenLeft = false;
      clearSubmittedSearch();
    }
    return true;
  }

  void retireClosedDraft(String expression) {
    if (isOpen ||
        isLeaving ||
        _openingExpression == null ||
        _openingExpression == expression) {
      return;
    }
    _draft = null;
    _openingExpression = expression;
    global.clearAllConditions();
    global.setQuery('');
    global.setScope(GlobalSearchScope.all);
  }

  void selectResult(String? id) {
    selectedResultId = id;
    _selectedNavigationIdentity = global.results
        .where((result) => result.id == id)
        .firstOrNull
        ?.navigationIdentity;
  }

  void reconcileSelection() {
    final selected = global.results
        .where((row) => row.id == selectedResultId)
        .firstOrNull;
    if (selected?.navigationIdentity != _selectedNavigationIdentity) {
      selectResult(null);
    }
  }

  static String listExpression(ContentRoute? route, String words) {
    if (route == null || route.isTopic) return '';
    if (route.isAdvancedTopicFilter) return route.topicFilterQuery;
    if (route.isSearchList) {
      return Uri.parse(route.feedPath!).queryParameters['q'] ?? '';
    }
    return [
      if (route.categoryId != null) 'category:${route.categoryId}',
      if (route.tagNames.isNotEmpty) 'tags:${route.tagNames.join('+')}',
      route.topicListSearch.isNotEmpty ? route.topicListSearch : words,
    ].where((part) => part.isNotEmpty).join(' ');
  }

  GlobalSearchExpression closedExpression(String expression) {
    try {
      return parseGlobalSearchExpression(
        expression,
        GlobalSearchScope.all,
        global.capabilities,
      );
    } on FormatException {
      return GlobalSearchExpression(expression, const [], null);
    }
  }

  void prepareOpening({
    required SearchPresentationSource source,
    SearchFocusMode? mode,
    GlobalSearchContext? context,
  }) {
    if (context != null) {
      global.clearAllConditions();
      global.setQuery('');
    }
    _openingExpression = source.expression;
    final route = source.route;
    final preferred = route == null
        ? null
        : ContentPageContract.resolve(route).searchScope ??
              global.scopes
                  .where(
                    (scope) =>
                        route.destination is ExtensionDestination &&
                        !scope.isCore &&
                        route.id.startsWith(scope.owner),
                  )
                  .firstOrNull;
    global.setPageContext(
      preferredScope: preferred,
      topicId: route?.topicId,
      topicTitle: route?.title,
    );
    final openingContext =
        context ??
        source.pluginContext ??
        (route?.isTopic == true || route?.isTopicList == true
            ? GlobalSearchContext(
                scope: GlobalSearchScope.forum,
                condition: route?.topicId != null
                    ? GlobalSearchCondition(
                        filterId: 'topicId',
                        value: ['${route!.topicId}'],
                      )
                    : route?.categoryId != null
                    ? GlobalSearchCondition(
                        filterId: 'category',
                        operator: 'any',
                        value: ['${route!.categoryId}'],
                      )
                    : null,
              )
            : null);
    if (mode != SearchFocusMode.contextual || openingContext == null) {
      if (mode == SearchFocusMode.global) {
        global.setContext(null);
        if (global.scope != GlobalSearchScope.forum ||
            global.conditions.isEmpty && !global.hasOrderFilter) {
          global.setScope(GlobalSearchScope.all);
        }
      }
      if (global.query.trim().isEmpty &&
          global.conditions.isEmpty &&
          !global.hasOrderFilter) {
        global.clearAllConditions();
        global.setScope(GlobalSearchScope.all);
        final seed = source.expression;
        if (seed.isNotEmpty) global.setQuery('$seed ');
      }
    } else {
      global.setContext(openingContext);
    }
  }
}

/// Captures the account and source destination before a mobile route closes.
final class SearchResultActivation {
  SearchResultActivation({
    required this.host,
    required this.lease,
    required this.site,
    required this.sourceRoute,
    required this.words,
    required this.result,
  });

  final Object host;
  final SiteLease lease;
  final String site;
  final ContentRoute? sourceRoute;
  final String words;
  final GlobalSearchResult result;

  bool canNavigate({
    required Object? currentHost,
    required Object? contextHost,
    required bool sourceOwnsInput,
    required ContentRoute? currentRoute,
    required String? searchSite,
    required String? activeSite,
  }) =>
      lease.isCurrent &&
      sourceOwnsInput &&
      sourceRoute?.sameDestinationAs(currentRoute) == true &&
      identical(host, currentHost) &&
      identical(host, contextHost) &&
      searchSite == site &&
      activeSite == site;

  String? wordsForDestination({
    required bool ownsInput,
    required Object? capturedTab,
    required Object? currentTab,
    required ContentRoute route,
    required ContentRoute? previousRoute,
  }) {
    if (!lease.isCurrent || !ownsInput || !identical(capturedTab, currentTab)) {
      return null;
    }
    final expected = result.destination;
    if (expected != null && route.destination.identity != expected.identity) {
      return null;
    }
    if (route.sameDestinationAs(previousRoute)) return null;
    return result.source is SearchCategoryHit || result.source is SearchTagHit
        ? ''
        : words;
  }
}
