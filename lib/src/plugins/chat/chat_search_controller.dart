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
  final Map<String, Timer> _globalTimers = {};
  final Map<String, Object> _globalRequests = {};
  final Map<String, VoidCallback> _globalFocus = {};
  bool _disposed = false;

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
    // Listeners may replace or cancel this operation while state is published.
    final run = Object();
    _globalRequests[siteUrl] = run;
    final lease = _requests.capture(siteUrl);
    _setGlobal(
      siteUrl,
      GlobalChatSearchState(
        query: query,
        sort: held.sort,
        phase: ChatSearchPhase.waiting,
      ),
    );
    if (_disposed ||
        !lease.isCurrent ||
        !identical(_globalRequests[siteUrl], run)) {
      return;
    }
    _globalTimers[siteUrl] = Timer(debounceDuration, () {
      if (!_disposed &&
          lease.isCurrent &&
          identical(_globalRequests[siteUrl], run)) {
        unawaited(_searchGlobal(siteUrl));
      }
    });
  }

  void setGlobalSort(String siteUrl, ChatSearchSort sort) {
    if (_disposed) return;
    final held = globalState(siteUrl);
    if (held.sort == sort) return;
    _cancelGlobal(siteUrl);
    unawaited(_searchGlobal(siteUrl, sort: sort));
  }

  Future<void> retryGlobal(String siteUrl) async {
    final held = globalState(siteUrl);
    if (_disposed || !held.hasQuery || held.loadingMore) return;
    _cancelGlobal(siteUrl);
    await _searchGlobal(siteUrl);
  }

  void loadMore(String siteUrl) {
    final held = globalState(siteUrl);
    if (_disposed || held.hits.isEmpty || !held.hasMore || held.loadingMore) {
      return;
    }
    unawaited(_searchGlobal(siteUrl, append: true));
  }

  Future<void> _searchGlobal(
    String siteUrl, {
    bool append = false,
    ChatSearchSort? sort,
  }) async {
    _globalTimers.remove(siteUrl)?.cancel();
    if (_disposed) return;
    final held = globalState(siteUrl);
    final term = held.query.trim();
    final requestedSort = sort ?? held.sort;
    if (term.isEmpty || term.length > maximumQueryLength) {
      _setGlobal(
        siteUrl,
        GlobalChatSearchState(
          query: held.query,
          sort: requestedSort,
          phase: term.isEmpty ? ChatSearchPhase.idle : ChatSearchPhase.failed,
          error: term.isEmpty
              ? null
              : 'Search terms must be at most $maximumQueryLength characters.',
        ),
      );
      return;
    }
    // Listeners may replace or cancel this operation while state is published.
    final run = Object();
    _globalRequests[siteUrl] = run;
    final lease = _requests.capture(siteUrl);
    bool current() =>
        !_disposed &&
        lease.isCurrent &&
        identical(_globalRequests[siteUrl], run);

    try {
      if (!current()) return;
      if (append) {
        _setGlobal(
          siteUrl,
          GlobalChatSearchState(
            query: held.query,
            sort: requestedSort,
            phase: ChatSearchPhase.results,
            hits: held.hits,
            hasMore: held.hasMore,
            nextOffset: held.nextOffset,
            loadingMore: true,
          ),
        );
      } else {
        _setGlobal(
          siteUrl,
          GlobalChatSearchState(
            query: held.query,
            sort: requestedSort,
            phase: ChatSearchPhase.loading,
          ),
        );
      }
      if (!current()) return;
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
        sort: requestedSort,
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
            sort: requestedSort,
            phase: hits.isEmpty
                ? ChatSearchPhase.empty
                : ChatSearchPhase.results,
            hits: hits,
            hasMore: page.hasMore,
            nextOffset: (append ? held.nextOffset : 0) + page.consumedCount,
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
                  sort: requestedSort,
                  phase: ChatSearchPhase.results,
                  hits: held.hits,
                  hasMore: held.hasMore,
                  nextOffset: held.nextOffset,
                  error: 'Could not load more chat results.',
                )
              : GlobalChatSearchState(
                  query: held.query,
                  sort: requestedSort,
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

  void _setGlobal(String siteUrl, GlobalChatSearchState state) {
    if (_disposed) return;
    _global[siteUrl] = state;
    final ref = _globalRefs[siteUrl];
    if (ref != null) ref.value = state;
  }

  void _cancelGlobal(String siteUrl) {
    _globalTimers.remove(siteUrl)?.cancel();
    _globalRequests.remove(siteUrl);
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
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _globalTimers.values) {
      timer.cancel();
    }
    _globalTimers.clear();
    _globalRequests.clear();
    for (final ref in _globalRefs.values) {
      ref.dispose();
    }
    _globalRefs.clear();
    _global.clear();
    _globalFocus.clear();
  }
}
