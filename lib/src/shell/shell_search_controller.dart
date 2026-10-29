import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_directory.dart';
import 'global_search_models.dart';
import 'recent_search_history.dart';

enum SearchFocusMode { global, contextual }

final class SearchFocusRequest {
  const SearchFocusRequest({required this.mode, this.context});

  final SearchFocusMode mode;
  final GlobalSearchContext? context;
}

class ShellSearchController extends ChangeNotifier {
  ShellSearchController({required this.history});

  final RecentSearchHistory history;

  String? _siteUrl;
  bool _authenticated = true;
  final Set<String> _anonymousSearchDenied = {};
  bool _panelOpen = false;
  ValueChanged<SearchFocusRequest>? _focusField;
  Object? _focusRegistration;
  Object? _activeField;
  bool _disposed = false;
  final Map<({String siteUrl, String tabId}), String> _startPageQueries = {};
  final Map<({String siteUrl, String tabId, String routeId}), String>
  _pageWords = {};

  final Map<({String siteUrl, String tabId}), UserDirectoryQuery>
  _usersQueries = {};

  UserDirectoryQuery usersQueryFor(String siteUrl, String? tabId) =>
      _usersQueries[(siteUrl: siteUrl, tabId: tabId ?? '')] ??
      const UserDirectoryQuery();

  bool replaceUsersQuery(
    String siteUrl,
    String? tabId,
    UserDirectoryQuery query,
  ) {
    if (_disposed) return false;
    final normalized = query.normalized();
    if (usersQueryFor(siteUrl, tabId) == normalized) return false;
    _usersQueries[(siteUrl: siteUrl, tabId: tabId ?? '')] = normalized;
    _notify();
    return true;
  }

  String wordsFor(String siteUrl, String? tabId, String routeId) =>
      routeId == 'users'
      ? usersQueryFor(siteUrl, tabId).search
      : _pageWords[(siteUrl: siteUrl, tabId: tabId ?? '', routeId: routeId)] ??
            '';

  void setPageWords(
    String siteUrl,
    String? tabId,
    String routeId,
    String query,
  ) {
    if (routeId == 'users') {
      replaceUsersQuery(
        siteUrl,
        tabId,
        usersQueryFor(siteUrl, tabId).copyWith(search: query),
      );
      return;
    }
    final key = (siteUrl: siteUrl, tabId: tabId ?? '', routeId: routeId);
    if (query.isEmpty) {
      _pageWords.remove(key);
    } else {
      _pageWords[key] = query;
    }
    _notify();
  }

  String? get siteUrl => _siteUrl;

  /// Core's `Guardian#can_search?`: a signed-in reader can always search, an
  /// anonymous one only where the site allows anonymous search.
  bool get canSearch =>
      _siteUrl != null &&
      (_authenticated || !_anonymousSearchDenied.contains(_siteUrl));
  bool get panelOpen => _panelOpen;
  List<String> get recentSearches => history.terms;

  String startPageQueryFor(String siteUrl, String tabId) =>
      _startPageQueries[(siteUrl: siteUrl, tabId: tabId)] ?? '';

  void setStartPageQuery(String siteUrl, String tabId, String query) {
    if (startPageQueryFor(siteUrl, tabId) == query) return;
    final key = (siteUrl: siteUrl, tabId: tabId);
    if (query.isEmpty) {
      _startPageQueries.remove(key);
    } else {
      _startPageQueries[key] = query;
    }
    _notify();
  }

  void retainTabs(Set<({String siteUrl, String tabId})> retainedTabs) {
    _pageWords.removeWhere(
      (key, _) =>
          key.tabId.isNotEmpty &&
          !retainedTabs.contains((siteUrl: key.siteUrl, tabId: key.tabId)),
    );
    _startPageQueries.removeWhere((key, _) => !retainedTabs.contains(key));
    _usersQueries.removeWhere((key, _) => !retainedTabs.contains(key));
  }

  bool ownsPanel(Object field) => identical(_activeField, field);

  void selectSite(
    String? siteUrl, {
    String? username,
    bool authenticated = true,
    bool logSearchQueries = true,
  }) {
    if (_disposed) return;
    final changed = history.configure(
      siteUrl: siteUrl,
      username: username,
      authenticated: authenticated,
      logSearchQueries: logSearchQueries,
    );
    final wasSearchable = canSearch;
    _authenticated = authenticated;
    if (_siteUrl != siteUrl) {
      _siteUrl = siteUrl;
      clear();
    } else if (!canSearch) {
      if (wasSearchable) clear();
    } else if (changed || !wasSearchable) {
      _notify();
      if (_panelOpen) unawaited(history.load());
    }
  }

  void allowAnonymousSearch(String siteUrl, bool allowed) {
    if (_disposed) return;
    final wasSearchable = canSearch;
    if (allowed) {
      _anonymousSearchDenied.remove(siteUrl);
    } else {
      _anonymousSearchDenied.add(siteUrl);
    }
    if (canSearch == wasSearchable) return;
    canSearch ? _notify() : clear();
  }

  void openPanel() {
    if (!canSearch) return;
    if (!_panelOpen) {
      _panelOpen = true;
      _notify();
    }
    unawaited(history.load());
  }

  void closePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    _notify();
  }

  void forget(String siteUrl) {
    _anonymousSearchDenied.remove(siteUrl);
    _pageWords.removeWhere((key, _) => key.siteUrl == siteUrl);
    _usersQueries.removeWhere((key, _) => key.siteUrl == siteUrl);
    _startPageQueries.removeWhere((key, _) => key.siteUrl == siteUrl);
    if (_siteUrl != siteUrl) return;
    history.forget(siteUrl);
    clear();
  }

  void clear() {
    _panelOpen = false;
    _notify();
  }

  VoidCallback registerFocus(
    Object field,
    ValueChanged<SearchFocusRequest> focus,
  ) {
    _focusRegistration = field;
    _focusField = focus;
    return () {
      if (identical(_focusRegistration, field)) {
        _focusRegistration = null;
        _focusField = null;
      }
      if (identical(_activeField, field)) {
        _activeField = null;
        closePanel();
      }
    };
  }

  void activateField(Object field) {
    if (!canSearch) return;
    if (!identical(_activeField, field)) {
      _activeField = field;
      _panelOpen = true;
      _notify();
      unawaited(history.load());
    } else {
      openPanel();
    }
  }

  void requestFocus({
    SearchFocusMode mode = SearchFocusMode.global,
    GlobalSearchContext? context,
  }) {
    if (!canSearch) return;
    _focusField?.call(SearchFocusRequest(mode: mode, context: context));
    openPanel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _usersQueries.clear();
    if (_siteUrl case final site?) history.forget(site);
    _focusField = null;
    _focusRegistration = null;
    _activeField = null;
    super.dispose();
  }
}
