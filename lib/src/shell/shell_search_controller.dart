import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../models/user_directory.dart';

enum SearchFocusMode { global, contextual }

typedef _RecentSearchRequest = ({String siteUrl, int revision});

class ShellSearchController extends ChangeNotifier {
  ShellSearchController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final ShellSearchApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;

  String? _siteUrl;
  bool _logSearchQueries = true;
  bool _panelOpen = false;
  List<String> _recentSearches = const [];
  ValueChanged<SearchFocusMode>? _focusField;
  Object? _focusRegistration;
  Object? _activeField;
  String? _recentSearchesLoadedFor;
  int _recentSearchesRevision = 0;
  _RecentSearchRequest? _recentSearchesRequest;
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
  bool get panelOpen => _panelOpen;
  List<String> get recentSearches => _recentSearches;

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

  void selectSite(String? siteUrl, {bool logSearchQueries = true}) {
    if (_siteUrl != siteUrl) {
      _siteUrl = siteUrl;
      _logSearchQueries = logSearchQueries;
      _forgetRecentSearches();
      clear();
      return;
    }

    if (_logSearchQueries == logSearchQueries) return;
    _logSearchQueries = logSearchQueries;
    _forgetRecentSearches();
    _notify();
    if (_logSearchQueries && _panelOpen) unawaited(_loadRecentSearches());
  }

  void openPanel() {
    if (_siteUrl == null) return;
    if (!_panelOpen) {
      _panelOpen = true;
      _notify();
    }
    unawaited(_loadRecentSearches());
  }

  void closePanel() {
    if (!_panelOpen) return;
    _panelOpen = false;
    _notify();
  }

  void forget(String siteUrl) {
    _pageWords.removeWhere((key, _) => key.siteUrl == siteUrl);
    _usersQueries.removeWhere((key, _) => key.siteUrl == siteUrl);
    _startPageQueries.removeWhere((key, _) => key.siteUrl == siteUrl);
    if (_siteUrl != siteUrl) return;
    _forgetRecentSearches();
    clear();
  }

  void _forgetRecentSearches() {
    _recentSearches = const [];
    _recentSearchesLoadedFor = null;
    _recentSearchesRevision++;
    _recentSearchesRequest = null;
  }

  void clear() {
    _panelOpen = false;
    _notify();
  }

  Future<void> _loadRecentSearches() async {
    final siteUrl = _siteUrl;
    final pending = _recentSearchesRequest;
    if (_disposed ||
        !_panelOpen ||
        siteUrl == null ||
        !_logSearchQueries ||
        (pending?.siteUrl == siteUrl &&
            pending?.revision == _recentSearchesRevision) ||
        _recentSearchesLoadedFor == siteUrl) {
      return;
    }
    final request = (siteUrl: siteUrl, revision: ++_recentSearchesRevision);
    _recentSearchesRequest = request;
    bool ownsRequest() =>
        !_disposed &&
        request.revision == _recentSearchesRevision &&
        request.siteUrl == _siteUrl &&
        _logSearchQueries;
    final lease = lifecycle.capture(siteUrl);
    try {
      final auth = await AccountRequestSession(
        siteUrl,
        lease,
      ).credentials(credentials);
      final apiKey = auth.apiKey;
      if (!lease.isCurrent || !ownsRequest()) return;
      if (apiKey == null) {
        _recentSearchesLoadedFor = siteUrl;
        return;
      }
      final clientId = auth.clientId;
      if (!lease.isCurrent || !ownsRequest()) return;
      final recent = await auth.run(
        () => api.recentSearches(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
        ),
      );
      if (!lease.isCurrent || !ownsRequest()) return;
      _recentSearches = recent;
      _recentSearchesLoadedFor = siteUrl;
      _notify();
    } catch (error, stackTrace) {
      if (lease.isCurrent && ownsRequest()) {
        _recentSearchesLoadedFor = siteUrl;
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'search.loadRecent',
          source: 'search',
          handled: true,
          degraded: false,
        );
      }
    } finally {
      if (_recentSearchesRequest == request) _recentSearchesRequest = null;
    }
  }

  VoidCallback registerFocus(
    Object field,
    ValueChanged<SearchFocusMode> focus,
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
    if (!identical(_activeField, field)) {
      _activeField = field;
      _panelOpen = true;
      _notify();
      unawaited(_loadRecentSearches());
    } else {
      openPanel();
    }
  }

  void requestFocus({SearchFocusMode mode = SearchFocusMode.global}) {
    if (_siteUrl == null) return;
    _focusField?.call(mode);
    openPanel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _usersQueries.clear();
    _forgetRecentSearches();
    _focusField = null;
    _focusRegistration = null;
    _activeField = null;
    super.dispose();
  }
}
