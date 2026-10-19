import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/recent_search_store.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import 'global_search_api.dart';
import 'global_search_filters.dart';
import 'global_search_models.dart';

enum RecentSearchClearOutcome { cleared, failed, superseded }

/// Owns the active account's history, including optimistic edits and removals.
class RecentSearchHistory extends ChangeNotifier {
  RecentSearchHistory({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    this.server,
    this.store = const RecentSearchStore(),
  });

  final GlobalSearchApi api;
  final ShellSearchApi? server;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final RecentSearchStore store;

  String? _siteUrl, _username;
  SiteLease? _lease;
  VoidCallback? _detach;
  bool _authenticated = true, _logSearchQueries = true, _disposed = false;
  int _generation = 0, _historyRevision = 0;
  List<String> _serverTerms = const [], _localTerms = const [];
  final _states = <String, GlobalSearchRequest>{};
  _RecentSearchRemovals _removals = _RecentSearchRemovals();
  final _pendingRemovalReads =
      <
        ({String site, String username, Object session}),
        _RecentSearchRemovals
      >{};
  bool _loaded = false, _cleared = false;
  Object? _loadRequest;

  bool get _current => !_disposed && _lease?.isCurrent == true;
  bool get _enabled => _current && _authenticated && _logSearchQueries;

  List<String> get terms => !_enabled
      ? const []
      : List.unmodifiable(
          {
            ..._localTerms,
            if (!_cleared) ..._serverTerms,
          }.where((term) => !_removals.removed.contains(term)).take(5),
        );

  GlobalSearchRequest? savedRequest(String term) =>
      _enabled ? _states[term] : null;

  bool configure({
    String? siteUrl,
    String? username,
    bool authenticated = true,
    bool logSearchQueries = true,
  }) {
    if (_disposed) return false;
    final lease = siteUrl == null ? null : lifecycle.capture(siteUrl);
    final changedAccount =
        _siteUrl != siteUrl ||
        _username != username ||
        _lease?.session != lease?.session ||
        _authenticated != authenticated;
    final changedPolicy = _logSearchQueries != logSearchQueries;
    if (!changedAccount && !changedPolicy) return false;
    _logSearchQueries = logSearchQueries;
    if (changedAccount) {
      _detach?.call();
      _reset();
      _siteUrl = siteUrl;
      _username = username;
      _authenticated = authenticated;
      _lease = lease;
      _detach = lease?.onRetire(() {
        _reset();
        _notify();
      });
      if (siteUrl != null &&
          username != null &&
          authenticated &&
          lease != null) {
        final key = (site: siteUrl, username: username, session: lease.session);
        final pending = _pendingRemovalReads[key];
        if (pending != null) {
          _removals = pending;
        } else {
          final removals = _removals..restoring = true;
          _pendingRemovalReads[key] = removals;
          unawaited(_restoreRemoved(key, lease, removals));
        }
      }
    } else {
      _resetServer();
      _historyRevision++;
    }
    _notify();
    return true;
  }

  void forget(String siteUrl) {
    if (_disposed || _siteUrl != siteUrl) return;
    _reset();
    _notify();
  }

  void _resetServer() {
    _serverTerms = const [];
    _loaded = false;
    _loadRequest = null;
  }

  void _reset() {
    _generation++;
    _historyRevision++;
    _resetServer();
    _localTerms = const [];
    _states.clear();
    _removals = _RecentSearchRemovals();
    _cleared = false;
  }

  Future<void> load() async {
    final site = _siteUrl, lease = _lease, source = server;
    if (!_enabled ||
        site == null ||
        lease == null ||
        source == null ||
        _loaded ||
        _loadRequest != null) {
      return;
    }
    final request = Object();
    _loadRequest = request;
    bool current() => _enabled && identical(_loadRequest, request);
    try {
      final auth = await AccountRequestSession(
        site,
        lease,
      ).credentials(credentials);
      if (!current()) return;
      final key = auth.apiKey;
      if (key == null) {
        _loaded = true;
        return;
      }
      final recent = await auth.run(
        () => source.recentSearches(
          siteUrl: site,
          apiKey: key,
          clientId: auth.clientId,
        ),
      );
      if (!current()) return;
      _serverTerms = List.unmodifiable(recent);
      _loaded = true;
      _notify();
    } catch (error, stackTrace) {
      if (current()) {
        _loaded = true;
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
      if (identical(_loadRequest, request)) _loadRequest = null;
    }
  }

  Future<void> _restoreRemoved(
    ({String site, String username, Object session}) key,
    SiteLease lease,
    _RecentSearchRemovals removals,
  ) async {
    try {
      final saved = await store.read(key.site, key.username);
      if (!lease.isCurrent) return;
      final merged = <String>{
        ...saved.where(
          (term) =>
              !removals.remembered.contains(term) &&
              !removals.removed.contains(term),
        ),
        ...removals.removed,
      };
      removals.removed
        ..clear()
        ..addAll(merged);
    } catch (_) {
    } finally {
      removals.restoring = false;
      removals.remembered.clear();
      if (lease.isCurrent && removals.saveAfterRestore) {
        _writeRemoved(key.site, key.username, removals.removed);
      }
      _pendingRemovalReads.remove(key);
      if (identical(_removals, removals)) _notify();
    }
  }

  void _saveRemoved() {
    final site = _siteUrl, username = _username;
    if (!_current || site == null || username == null) return;
    if (_removals.restoring) {
      _removals.saveAfterRestore = true;
    } else {
      _writeRemoved(site, username, _removals.removed);
    }
  }

  void _writeRemoved(String site, String username, Set<String> removed) {
    unawaited(
      store.write(site, username, Set.of(removed)).catchError((Object _) {}),
    );
  }

  void remember(GlobalSearchRequest request) {
    if (!_enabled || request.query.trim().isEmpty) return;
    final term = globalSearchTerm(request).trim();
    if (term.isEmpty) return;
    _removals.removed.remove(term);
    if (_removals.restoring) _removals.remembered.add(term);
    _saveRemoved();
    _localTerms = List.unmodifiable({term, ...terms}.take(5));
    _states[term] = request;
    _states.removeWhere((key, _) => !_localTerms.contains(key));
    _historyRevision++;
    _notify();
  }

  void remove(String term) {
    if (!_current) return;
    _removals.removed
      ..remove(term)
      ..add(term);
    _removals.remembered.remove(term);
    _saveRemoved();
    _localTerms = List.unmodifiable(
      _localTerms.where((value) => value != term),
    );
    _states.remove(term);
    _historyRevision++;
    _notify();
  }

  Future<RecentSearchClearOutcome> clear() async {
    if (_disposed) return RecentSearchClearOutcome.superseded;
    final site = _siteUrl, lease = _lease, generation = _generation;
    final previous = _localTerms, wasCleared = _cleared;
    final revision = ++_historyRevision;
    _localTerms = const [];
    _cleared = true;
    _notify();
    if (site == null || lease == null || !_authenticated) {
      return RecentSearchClearOutcome.cleared;
    }
    bool current() => _current && generation == _generation;
    bool ownsEdit() => current() && revision == _historyRevision;
    try {
      final auth = await AccountRequestSession(
        site,
        lease,
      ).credentials(credentials);
      if (!current()) return RecentSearchClearOutcome.superseded;
      final key = auth.apiKey;
      if (key == null) return RecentSearchClearOutcome.cleared;
      await auth.run(
        () => api.clearRecentSearches(
          siteUrl: site,
          apiKey: key,
          clientId: auth.clientId,
        ),
      );
      return ownsEdit()
          ? RecentSearchClearOutcome.cleared
          : RecentSearchClearOutcome.superseded;
    } catch (_) {
      if (!ownsEdit()) return RecentSearchClearOutcome.superseded;
      _localTerms = previous;
      _cleared = wasCleared;
      _notify();
      return RecentSearchClearOutcome.failed;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _detach?.call();
    _reset();
    _pendingRemovalReads.clear();
    super.dispose();
  }
}

final class _RecentSearchRemovals {
  final removed = <String>{};
  final remembered = <String>{};
  bool restoring = false, saveAfterRestore = false;
}
