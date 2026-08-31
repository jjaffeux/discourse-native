// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../diagnostics/diagnostics_controller.dart';
import '../../foundation/frame_safe_notifier.dart';
import '../../plugin_api/core_plugin_host.dart';
import 'chat_api.dart';
import 'chat_search.dart';

enum ChatSearchPhase { idle, waiting, loading, results, empty, failed }

@immutable
final class GlobalChatSearchState {
  const GlobalChatSearchState({
    this.query = '',
    this.sort = ChatSearchSort.relevance,
    this.phase = ChatSearchPhase.idle,
    this.hits = const [],
    this.hasMore = false,
    this.nextOffset = 0,
    this.loadingMore = false,
    this.error,
  });

  final String query;
  final ChatSearchSort sort;
  final ChatSearchPhase phase;
  final List<ChatSearchHit> hits;
  final bool hasMore;
  final int nextOffset;
  final bool loadingMore;
  final String? error;

  bool get hasQuery => query.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is GlobalChatSearchState &&
      other.query == query &&
      other.sort == sort &&
      other.phase == phase &&
      listEquals(other.hits, hits) &&
      other.hasMore == hasMore &&
      other.nextOffset == nextOffset &&
      other.loadingMore == loadingMore &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    query,
    sort,
    phase,
    Object.hashAll(hits),
    hasMore,
    nextOffset,
    loadingMore,
    error,
  );
}

@immutable
final class ScopedChatSearchState {
  const ScopedChatSearchState({
    this.open = false,
    this.query = '',
    this.phase = ChatSearchPhase.idle,
    this.hits = const [],
    this.selectedIndex = 0,
    this.selectionRevision = 0,
    this.error,
  });

  final bool open;
  final String query;
  final ChatSearchPhase phase;
  final List<ChatSearchHit> hits;
  final int selectedIndex;
  final int selectionRevision;
  final String? error;

  ChatSearchHit? get selectedHit => hits.isEmpty ? null : hits[selectedIndex];

  @override
  bool operator ==(Object other) =>
      other is ScopedChatSearchState &&
      other.open == open &&
      other.query == query &&
      other.phase == phase &&
      listEquals(other.hits, hits) &&
      other.selectedIndex == selectedIndex &&
      other.selectionRevision == selectionRevision &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    open,
    query,
    phase,
    Object.hashAll(hits),
    selectedIndex,
    selectionRevision,
    error,
  );
}

final class ChatSearchController {
  ChatSearchController({
    required this.api,
    required PluginRequestHost requests,
    required Store store,
    this.reporter = const PluginDiagnosticsReporter.noop(),
    this.debounceDuration = const Duration(milliseconds: 400),
  }) : assert(debounceDuration >= Duration.zero),
       _requests = requests,
       _store = store;

  final ChatApi api;
  final PluginRequestHost _requests;
  final Store _store;
  final PluginDiagnosticsReporter reporter;
  final Duration debounceDuration;

  static const int maximumQueryLength = 2048;

  final Map<String, GlobalChatSearchState> _global = {};
  final Map<String, FrameSafeValueNotifier<GlobalChatSearchState>> _globalRefs =
      {};
  final Map<String, ScopedChatSearchState> _scoped = {};
  final Map<String, FrameSafeValueNotifier<ScopedChatSearchState>> _scopedRefs =
      {};
  final Map<String, Timer> _globalTimers = {};
  final Map<String, Timer> _scopedTimers = {};
  final Map<String, Object> _globalRequests = {};
  final Map<String, Object> _scopedRequests = {};
  final Map<String, VoidCallback> _globalFocus = {};
  bool _disposed = false;

  static String _scopedKey(String siteUrl, int channelId) =>
      '$siteUrl~$channelId';

  ValueListenable<GlobalChatSearchState> globalRef(String siteUrl) =>
      _globalRefs.putIfAbsent(
        siteUrl,
        () => FrameSafeValueNotifier(
          _global[siteUrl] ?? const GlobalChatSearchState(),
        ),
      );

  GlobalChatSearchState globalState(String siteUrl) =>
      _global[siteUrl] ?? const GlobalChatSearchState();

  VoidCallback registerGlobalFocus(String siteUrl, VoidCallback focus) {
    if (_disposed) return () {};
    _globalFocus[siteUrl] = focus;
    return () {
      if (identical(_globalFocus[siteUrl], focus)) {
        _globalFocus.remove(siteUrl);
      }
    };
  }

  void requestGlobalFocus(String siteUrl) {
    if (!_disposed) _globalFocus[siteUrl]?.call();
  }

  ValueListenable<ScopedChatSearchState> scopedRef(
    String siteUrl,
    int channelId,
  ) {
    final key = _scopedKey(siteUrl, channelId);
    return _scopedRefs.putIfAbsent(
      key,
      () =>
          FrameSafeValueNotifier(_scoped[key] ?? const ScopedChatSearchState()),
    );
  }

  ScopedChatSearchState scopedState(String siteUrl, int channelId) =>
      _scoped[_scopedKey(siteUrl, channelId)] ?? const ScopedChatSearchState();

  void setGlobalQuery(String siteUrl, String query) {
    if (_disposed) return;
    final held = globalState(siteUrl);
    if (held.query == query) return;
    _cancelGlobal(siteUrl);
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _setGlobal(siteUrl, GlobalChatSearchState(query: query, sort: held.sort));
      return;
    }
    if (trimmed.length > maximumQueryLength) {
      _setGlobal(
        siteUrl,
        GlobalChatSearchState(
          query: query,
          sort: held.sort,
          phase: ChatSearchPhase.failed,
          error: 'Search terms must be at most $maximumQueryLength characters.',
        ),
      );
      return;
    }
    _setGlobal(
      siteUrl,
      GlobalChatSearchState(
        query: query,
        sort: held.sort,
        phase: ChatSearchPhase.waiting,
      ),
    );
    _globalTimers[siteUrl] = Timer(
      debounceDuration,
      () => _searchGlobal(siteUrl),
    );
  }

  void setGlobalSort(String siteUrl, ChatSearchSort sort) {
    if (_disposed) return;
    final held = globalState(siteUrl);
    if (held.sort == sort) return;
    _cancelGlobal(siteUrl);
    final phase = held.hasQuery
        ? ChatSearchPhase.loading
        : ChatSearchPhase.idle;
    _setGlobal(
      siteUrl,
      GlobalChatSearchState(query: held.query, sort: sort, phase: phase),
    );
    if (held.hasQuery) unawaited(_searchGlobal(siteUrl));
  }

  void retryGlobal(String siteUrl) {
    final held = globalState(siteUrl);
    if (_disposed || !held.hasQuery || held.loadingMore) return;
    _cancelGlobal(siteUrl);
    _setGlobal(
      siteUrl,
      GlobalChatSearchState(
        query: held.query,
        sort: held.sort,
        phase: ChatSearchPhase.loading,
      ),
    );
    unawaited(_searchGlobal(siteUrl));
  }

  void loadMore(String siteUrl) {
    final held = globalState(siteUrl);
    if (_disposed || held.hits.isEmpty || !held.hasMore || held.loadingMore) {
      return;
    }
    _globalRequests.remove(siteUrl);
    _setGlobal(
      siteUrl,
      GlobalChatSearchState(
        query: held.query,
        sort: held.sort,
        phase: ChatSearchPhase.results,
        hits: held.hits,
        hasMore: held.hasMore,
        nextOffset: held.nextOffset,
        loadingMore: true,
      ),
    );
    unawaited(_searchGlobal(siteUrl, append: true));
  }

  Future<void> _searchGlobal(String siteUrl, {bool append = false}) async {
    _globalTimers.remove(siteUrl)?.cancel();
    if (_disposed) return;
    final held = globalState(siteUrl);
    final term = held.query.trim();
    if (term.isEmpty) return;
    if (!append) {
      _setGlobal(
        siteUrl,
        GlobalChatSearchState(
          query: held.query,
          sort: held.sort,
          phase: ChatSearchPhase.loading,
        ),
      );
    }
    final run = Object();
    _globalRequests[siteUrl] = run;
    final lease = _requests.capture(siteUrl);
    bool current() =>
        !_disposed &&
        lease.isCurrent &&
        identical(_globalRequests[siteUrl], run);

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!current()) return;
      if (apiKey == null) throw StateError('Chat search requires an account.');
      final clientId = requestCredentials.clientId;
      if (!current()) return;
      final page = await api.searchChatMessages(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        query: term,
        sort: held.sort,
        offset: append ? held.nextOffset : 0,
      );
      if (!current()) return;
      lease.commit(() {
        _store.putAll(siteUrl, page.hits.map((hit) => hit.message));
        final hits = append ? _appendUnique(held.hits, page.hits) : page.hits;
        _setGlobal(
          siteUrl,
          GlobalChatSearchState(
            query: held.query,
            sort: held.sort,
            phase: hits.isEmpty
                ? ChatSearchPhase.empty
                : ChatSearchPhase.results,
            hits: hits,
            hasMore: page.hasMore,
            nextOffset: held.nextOffset + page.consumedCount,
          ),
        );
      });
    } catch (error, stackTrace) {
      if (!current()) return;
      _report(error, stackTrace, 'chat.search');
      lease.commit(() {
        _setGlobal(
          siteUrl,
          append
              ? GlobalChatSearchState(
                  query: held.query,
                  sort: held.sort,
                  phase: ChatSearchPhase.results,
                  hits: held.hits,
                  hasMore: held.hasMore,
                  nextOffset: held.nextOffset,
                  error: 'Could not load more chat results.',
                )
              : GlobalChatSearchState(
                  query: held.query,
                  sort: held.sort,
                  phase: ChatSearchPhase.failed,
                  error: 'Could not search Chat. Try again.',
                ),
        );
      });
    } finally {
      if (identical(_globalRequests[siteUrl], run)) {
        _globalRequests.remove(siteUrl);
      }
    }
  }

  static List<ChatSearchHit> _appendUnique(
    List<ChatSearchHit> held,
    List<ChatSearchHit> incoming,
  ) {
    final ids = held.map((hit) => hit.id).toSet();
    return List.unmodifiable([
      ...held,
      for (final hit in incoming)
        if (ids.add(hit.id)) hit,
    ]);
  }

  void toggleScoped(String siteUrl, int channelId) {
    final held = scopedState(siteUrl, channelId);
    if (held.open) {
      closeScoped(siteUrl, channelId);
    } else {
      openScoped(siteUrl, channelId);
    }
  }

  void openScoped(String siteUrl, int channelId) {
    if (_disposed) return;
    final held = scopedState(siteUrl, channelId);
    _setScoped(
      siteUrl,
      channelId,
      ScopedChatSearchState(
        open: true,
        query: held.query,
        phase: held.phase,
        hits: held.hits,
        selectedIndex: held.selectedIndex,
        selectionRevision: held.selectionRevision,
        error: held.error,
      ),
    );
  }

  void closeScoped(String siteUrl, int channelId) {
    final key = _scopedKey(siteUrl, channelId);
    _cancelScoped(key);
    _setScoped(siteUrl, channelId, const ScopedChatSearchState());
  }

  void setScopedQuery(String siteUrl, int channelId, String query) {
    if (_disposed) return;
    final key = _scopedKey(siteUrl, channelId);
    final held = scopedState(siteUrl, channelId);
    if (held.query == query) return;
    _cancelScoped(key);
    final term = query.trim();
    if (term.isEmpty) {
      _setScoped(
        siteUrl,
        channelId,
        ScopedChatSearchState(
          open: true,
          query: query,
          selectionRevision: held.selectionRevision,
        ),
      );
      return;
    }
    if (term.length > maximumQueryLength) {
      _setScoped(
        siteUrl,
        channelId,
        ScopedChatSearchState(
          open: true,
          query: query,
          phase: ChatSearchPhase.failed,
          selectionRevision: held.selectionRevision,
          error: 'Search terms must be at most $maximumQueryLength characters.',
        ),
      );
      return;
    }
    _setScoped(
      siteUrl,
      channelId,
      ScopedChatSearchState(
        open: true,
        query: query,
        phase: ChatSearchPhase.waiting,
        selectionRevision: held.selectionRevision,
      ),
    );
    _scopedTimers[key] = Timer(
      debounceDuration,
      () => _searchScoped(siteUrl, channelId),
    );
  }

  void retryScoped(String siteUrl, int channelId) {
    final held = scopedState(siteUrl, channelId);
    if (_disposed || held.query.trim().isEmpty) return;
    final key = _scopedKey(siteUrl, channelId);
    _cancelScoped(key);
    _setScoped(
      siteUrl,
      channelId,
      ScopedChatSearchState(
        open: true,
        query: held.query,
        phase: ChatSearchPhase.loading,
        selectionRevision: held.selectionRevision,
      ),
    );
    unawaited(_searchScoped(siteUrl, channelId));
  }

  Future<void> _searchScoped(String siteUrl, int channelId) async {
    final key = _scopedKey(siteUrl, channelId);
    _scopedTimers.remove(key)?.cancel();
    if (_disposed) return;
    final held = scopedState(siteUrl, channelId);
    final term = held.query.trim();
    if (!held.open || term.isEmpty) return;
    _setScoped(
      siteUrl,
      channelId,
      ScopedChatSearchState(
        open: true,
        query: held.query,
        phase: ChatSearchPhase.loading,
        selectionRevision: held.selectionRevision,
      ),
    );
    final run = Object();
    _scopedRequests[key] = run;
    final lease = _requests.capture(siteUrl);
    bool current() =>
        !_disposed &&
        lease.isCurrent &&
        identical(_scopedRequests[key], run) &&
        scopedState(siteUrl, channelId).open;

    try {
      final requestCredentials = await _requests.credentialsFor(siteUrl);
      final apiKey = requestCredentials.apiKey;
      if (!current()) return;
      if (apiKey == null) throw StateError('Chat search requires an account.');
      final clientId = requestCredentials.clientId;
      if (!current()) return;
      final page = await api.searchChatMessages(
        siteUrl: siteUrl,
        apiKey: apiKey,
        clientId: clientId,
        query: term,
        channelId: channelId,
        sort: ChatSearchSort.latest,
        excludeThreads: true,
      );
      if (!current()) return;
      lease.commit(() {
        _store.putAll(siteUrl, page.hits.map((hit) => hit.message));
        _setScoped(
          siteUrl,
          channelId,
          ScopedChatSearchState(
            open: true,
            query: held.query,
            phase: page.hits.isEmpty
                ? ChatSearchPhase.empty
                : ChatSearchPhase.results,
            hits: page.hits,
            selectionRevision:
                held.selectionRevision + (page.hits.isEmpty ? 0 : 1),
          ),
        );
      });
    } catch (error, stackTrace) {
      if (!current()) return;
      _report(error, stackTrace, 'chat.searchChannel');
      lease.commit(() {
        _setScoped(
          siteUrl,
          channelId,
          ScopedChatSearchState(
            open: true,
            query: held.query,
            phase: ChatSearchPhase.failed,
            selectionRevision: held.selectionRevision,
            error: 'Could not search this channel. Try again.',
          ),
        );
      });
    } finally {
      if (identical(_scopedRequests[key], run)) _scopedRequests.remove(key);
    }
  }

  void selectPrevious(String siteUrl, int channelId) =>
      _moveSelection(siteUrl, channelId, 1);

  void selectNext(String siteUrl, int channelId) =>
      _moveSelection(siteUrl, channelId, -1);

  void _moveSelection(String siteUrl, int channelId, int delta) {
    final held = scopedState(siteUrl, channelId);
    if (_disposed || held.hits.isEmpty) return;
    final index = (held.selectedIndex + delta) % held.hits.length;
    _setScoped(
      siteUrl,
      channelId,
      ScopedChatSearchState(
        open: true,
        query: held.query,
        phase: ChatSearchPhase.results,
        hits: held.hits,
        selectedIndex: index,
        selectionRevision: held.selectionRevision + 1,
      ),
    );
  }

  void _setGlobal(String siteUrl, GlobalChatSearchState state) {
    if (_disposed) return;
    _global[siteUrl] = state;
    final ref = _globalRefs[siteUrl];
    if (ref != null) ref.value = state;
  }

  void _setScoped(String siteUrl, int channelId, ScopedChatSearchState state) {
    if (_disposed) return;
    final key = _scopedKey(siteUrl, channelId);
    _scoped[key] = state;
    final ref = _scopedRefs[key];
    if (ref != null) ref.value = state;
  }

  void _cancelGlobal(String siteUrl) {
    _globalTimers.remove(siteUrl)?.cancel();
    _globalRequests.remove(siteUrl);
  }

  void _cancelScoped(String key) {
    _scopedTimers.remove(key)?.cancel();
    _scopedRequests.remove(key);
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    reporter.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'chat',
      handled: true,
      degraded: true,
    );
  }

  void forget(String siteUrl) {
    _cancelGlobal(siteUrl);
    _global.remove(siteUrl);
    _globalFocus.remove(siteUrl);
    final globalRef = _globalRefs.remove(siteUrl);
    globalRef?.value = const GlobalChatSearchState();

    final prefix = '$siteUrl~';
    for (final key
        in _scopedTimers.keys.where((key) => key.startsWith(prefix)).toList()) {
      _cancelScoped(key);
    }
    _scoped.removeWhere((key, _) => key.startsWith(prefix));
    final forgotten = <FrameSafeValueNotifier<ScopedChatSearchState>>[];
    _scopedRefs.removeWhere((key, ref) {
      if (!key.startsWith(prefix)) return false;
      forgotten.add(ref);
      return true;
    });
    for (final ref in forgotten) {
      ref.value = const ScopedChatSearchState();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in [..._globalTimers.values, ..._scopedTimers.values]) {
      timer.cancel();
    }
    _globalTimers.clear();
    _scopedTimers.clear();
    _globalRequests.clear();
    _scopedRequests.clear();
    for (final ref in _globalRefs.values) {
      ref.dispose();
    }
    for (final ref in _scopedRefs.values) {
      ref.dispose();
    }
    _globalRefs.clear();
    _scopedRefs.clear();
    _global.clear();
    _scoped.clear();
    _globalFocus.clear();
  }
}
