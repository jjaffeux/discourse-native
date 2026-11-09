// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

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
    this.debounceDuration = const Duration(milliseconds: 400),
  }) : assert(debounceDuration >= Duration.zero),
       _requests = requests;

  final ChatApi api;
  final PluginRequestHost _requests;

  final Duration debounceDuration;

  static const int maximumQueryLength = 2048;

  final Map<String, _GlobalChatSearchAccount> _accounts = {};
  bool _disposed = false;

  _GlobalChatSearchAccount? _account(String siteUrl) {
    if (_disposed) return null;
    final held = _accounts[siteUrl];
    if (held?.lease.isCurrent == true) return held;
    if (held != null) _retire(siteUrl, held);
    if (_disposed) return null;
    final successor = _accounts[siteUrl];
    if (successor != null) return successor;
    final account = _GlobalChatSearchAccount(_requests.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() => _retire(siteUrl, account));
    return account;
  }

  bool _owns(String siteUrl, _GlobalChatSearchAccount account) =>
      !_disposed &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account);

  ValueListenable<GlobalChatSearchState> globalRef(String siteUrl) =>
      _account(siteUrl)?.ref ??
      FrameSafeValueNotifier(const GlobalChatSearchState());

  /// Checks rendered account authority without admitting a successor account.
  bool isCurrentGlobalRef(
    String siteUrl,
    ValueListenable<GlobalChatSearchState> ref,
  ) {
    final account = _accounts[siteUrl];
    return account != null &&
        _owns(siteUrl, account) &&
        identical(account.ref, ref);
  }

  GlobalChatSearchState globalState(String siteUrl) {
    final account = _accounts[siteUrl];
    return !_disposed && account?.lease.isCurrent == true
        ? account!.ref.value
        : const GlobalChatSearchState();
  }

  void setGlobalQuery(String siteUrl, String query) {
    final account = _account(siteUrl);
    if (account == null) return;
    final held = account.ref.value;
    if (held.query == query) return;
    _cancelGlobal(account);
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _setGlobal(
        siteUrl,
        account,
        GlobalChatSearchState(query: query, sort: held.sort),
      );
      return;
    }
    if (trimmed.length > maximumQueryLength) {
      _setGlobal(
        siteUrl,
        account,
        GlobalChatSearchState(
          query: query,
          sort: held.sort,
          phase: ChatSearchPhase.failed,
          error: appL10n.searchTermsMustBeAtMostCharacters(
            (maximumQueryLength).toString(),
          ),
        ),
      );
      return;
    }
    // Listeners may replace or cancel this operation while state is published.
    final run = Object();
    account.request = run;
    final lease = account.lease;
    _setGlobal(
      siteUrl,
      account,
      GlobalChatSearchState(
        query: query,
        sort: held.sort,
        phase: ChatSearchPhase.waiting,
      ),
    );
    if (!_owns(siteUrl, account) ||
        !lease.isCurrent ||
        !identical(account.request, run)) {
      return;
    }
    account.timer = Timer(debounceDuration, () {
      if (_owns(siteUrl, account) &&
          lease.isCurrent &&
          identical(account.request, run)) {
        unawaited(_searchGlobal(siteUrl, account));
      }
    });
  }

  void setGlobalSort(String siteUrl, ChatSearchSort sort) {
    final account = _account(siteUrl);
    if (account == null) return;
    final held = account.ref.value;
    if (held.sort == sort) return;
    _cancelGlobal(account);
    unawaited(_searchGlobal(siteUrl, account, sort: sort));
  }

  Future<void> retryGlobal(String siteUrl) async {
    final account = _accounts[siteUrl];
    if (account == null || !_owns(siteUrl, account)) return;
    final held = account.ref.value;
    if (!held.hasQuery || held.loadingMore) return;
    _cancelGlobal(account);
    await _searchGlobal(siteUrl, account);
  }

  void loadMore(String siteUrl) {
    final account = _accounts[siteUrl];
    if (account == null || !_owns(siteUrl, account)) return;
    final held = account.ref.value;
    if (held.hits.isEmpty || !held.hasMore || held.loadingMore) {
      return;
    }
    unawaited(_searchGlobal(siteUrl, account, append: true));
  }

  Future<void> _searchGlobal(
    String siteUrl,
    _GlobalChatSearchAccount account, {
    bool append = false,
    ChatSearchSort? sort,
  }) async {
    account.timer?.cancel();
    account.timer = null;
    if (!_owns(siteUrl, account)) return;
    final held = account.ref.value;
    final term = held.query.trim();
    final requestedSort = sort ?? held.sort;
    if (term.isEmpty || term.length > maximumQueryLength) {
      _setGlobal(
        siteUrl,
        account,
        GlobalChatSearchState(
          query: held.query,
          sort: requestedSort,
          phase: term.isEmpty ? ChatSearchPhase.idle : ChatSearchPhase.failed,
          error: term.isEmpty
              ? null
              : appL10n.searchTermsMustBeAtMostCharacters(
                  (maximumQueryLength).toString(),
                ),
        ),
      );
      return;
    }
    // Listeners may replace or cancel this operation while state is published.
    final run = Object();
    account.request = run;
    final lease = account.lease;
    bool current() =>
        _owns(siteUrl, account) &&
        lease.isCurrent &&
        identical(account.request, run);

    try {
      if (!current()) return;
      if (append) {
        _setGlobal(
          siteUrl,
          account,
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
          account,
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
      final page = await requestCredentials.run(
        () => api.searchChatMessages(
          siteUrl: siteUrl,
          apiKey: apiKey,
          clientId: clientId,
          query: term,
          sort: requestedSort,
          offset: append ? held.nextOffset : 0,
        ),
      );
      if (!current()) return;
      lease.commit(() {
        final hits = append ? _appendUnique(held.hits, page.hits) : page.hits;
        _setGlobal(
          siteUrl,
          account,
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
    } catch (error) {
      if (!current()) return;

      lease.commit(() {
        _setGlobal(
          siteUrl,
          account,
          append
              ? GlobalChatSearchState(
                  query: held.query,
                  sort: requestedSort,
                  phase: ChatSearchPhase.results,
                  hits: held.hits,
                  hasMore: held.hasMore,
                  nextOffset: held.nextOffset,
                  error: appL10n.couldNotLoadMoreChatResults,
                )
              : GlobalChatSearchState(
                  query: held.query,
                  sort: requestedSort,
                  phase: ChatSearchPhase.failed,
                  error: appL10n.couldNotSearchChatTryAgain,
                ),
        );
      });
    } finally {
      if (identical(account.request, run)) {
        account.request = null;
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

  void _setGlobal(
    String siteUrl,
    _GlobalChatSearchAccount account,
    GlobalChatSearchState state,
  ) {
    if (_owns(siteUrl, account)) account.ref.value = state;
  }

  void _cancelGlobal(_GlobalChatSearchAccount account) {
    account.timer?.cancel();
    account.timer = null;
    account.request = null;
  }

  void _retire(String siteUrl, _GlobalChatSearchAccount account) {
    if (!identical(_accounts[siteUrl], account)) return;
    _accounts.remove(siteUrl);
    account.detach?.call();
    account.detach = null;
    _cancelGlobal(account);
    account.ref.value = const GlobalChatSearchState();
  }

  void forget(String siteUrl) {
    final account = _accounts[siteUrl];
    if (account != null) _retire(siteUrl, account);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final entry in _accounts.entries.toList()) {
      _retire(entry.key, entry.value);
    }
  }
}

final class _GlobalChatSearchAccount {
  _GlobalChatSearchAccount(this.lease);

  final PluginSiteLease lease;
  final ref = FrameSafeValueNotifier(const GlobalChatSearchState());
  Timer? timer;
  Object? request;
  VoidCallback? detach;
}
