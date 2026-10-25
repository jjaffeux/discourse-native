import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/user_directory_api.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/user_directory.dart';

@immutable
final class UserDirectoryState {
  factory UserDirectoryState({
    List<UserDirectoryItem> items = const [],
    List<UserDirectoryColumn> columns = const [],
    List<UserDirectoryColumn> availableColumns = const [],
    List<String> groupNames = const [],
    bool canManageColumns = false,
    int totalRows = 0,
    int nextPage = 0,
    DateTime? lastUpdatedAt,
    bool hasMore = false,
    bool loading = false,
    bool loadingMore = false,
    bool loaded = false,
    String? error,
    bool pageError = false,
  }) => UserDirectoryState._(
    items: List.unmodifiable(items),
    columns: List.unmodifiable(columns),
    availableColumns: List.unmodifiable(availableColumns),
    groupNames: List.unmodifiable(groupNames),
    canManageColumns: canManageColumns,
    totalRows: totalRows,
    nextPage: nextPage,
    lastUpdatedAt: lastUpdatedAt,
    hasMore: hasMore,
    loading: loading,
    loadingMore: loadingMore,
    loaded: loaded,
    error: error,
    pageError: pageError,
  );

  const UserDirectoryState.empty() : this._();

  const UserDirectoryState._({
    this.items = const [],
    this.columns = const [],
    this.availableColumns = const [],
    this.groupNames = const [],
    this.canManageColumns = false,
    this.totalRows = 0,
    this.nextPage = 0,
    this.lastUpdatedAt,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.pageError = false,
  });

  final List<UserDirectoryItem> items;
  final List<UserDirectoryColumn> columns;
  final List<UserDirectoryColumn> availableColumns;
  final List<String> groupNames;
  final bool canManageColumns;
  final int totalRows;
  final int nextPage;
  final DateTime? lastUpdatedAt;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final bool pageError;
}

final class _DirectoryProjection {
  const _DirectoryProjection(
    this.state,
    this.generation, {
    required this.rowsGeneration,
  });

  final UserDirectoryState state;
  final Object generation;
  final Object rowsGeneration;
}

final class _DirectoryAccount {
  _DirectoryAccount(this.lease);

  static const cachedQueries = 16;
  final SiteLease lease;
  final Map<UserDirectoryQuery, _DirectoryProjection> states = {};
  Object metadataGeneration = Object();
  UserDirectoryMetadata? metadata;
  Future<UserDirectoryMetadata>? metadataLoad;
  final Map<UserDirectoryQuery, Object> requests = {};
  Object? columnUpdate;
  void Function()? detach;

  UserDirectoryState stateFor(UserDirectoryQuery query) {
    final held = states[query];
    if (held != null &&
        (identical(held.generation, metadataGeneration) ||
            metadata == null ||
            requests.containsKey(query))) {
      return held.state;
    }
    final shared = metadata;
    return shared == null
        ? const UserDirectoryState.empty()
        : UserDirectoryState(
            columns: shared.columns,
            availableColumns: shared.availableColumns,
            groupNames: shared.groupNames,
            canManageColumns: shared.canManageColumns,
          );
  }

  void touch(UserDirectoryQuery query) {
    final held = states.remove(query);
    if (held != null) states[query] = held;
  }

  void trim() {
    for (final query
        in states.keys
            .take((states.length - cachedQueries).clamp(0, states.length))
            .toList()) {
      states.remove(query);
      requests.remove(query);
    }
  }

  void refreshMetadata() {
    metadataGeneration = Object();
    metadata = null;
    metadataLoad?.ignore();
    metadataLoad = null;
  }

  void clearQueries() {
    states.clear();
    refreshMetadata();
    requests.clear();
  }

  void dispose() {
    detach?.call();
    detach = null;
    clearQueries();
    columnUpdate = null;
  }
}

final class UserDirectoryController extends FrameSafeNotifier {
  UserDirectoryController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final UserDirectoryApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;

  final Map<String, _DirectoryAccount> _accounts = {};

  _DirectoryAccount? _accountFor(String siteUrl) {
    final account = _accounts[siteUrl];
    return account?.lease.isCurrent == true ? account : null;
  }

  _DirectoryAccount _ensureAccount(String siteUrl) {
    final held = _accountFor(siteUrl);
    if (held != null) return held;
    final account = _DirectoryAccount(lifecycle.capture(siteUrl));
    _accounts[siteUrl] = account;
    account.detach = account.lease.onRetire(() {
      final owned = identical(_accounts[siteUrl], account);
      if (owned) _accounts.remove(siteUrl);
      account.dispose();
      if (owned) notifySafely();
    });
    return account;
  }

  UserDirectoryState stateFor(String siteUrl, UserDirectoryQuery query) =>
      _accountFor(siteUrl)?.stateFor(query) ?? const UserDirectoryState.empty();

  bool updatingColumnsFor(String siteUrl) =>
      _accountFor(siteUrl)?.columnUpdate != null;

  Future<void> load(
    DiscourseInstance instance, {
    required UserDirectoryQuery query,
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed) return;
    final account = _ensureAccount(instance.url);
    final projection = account.states[query];
    final held = projection?.state ?? account.stateFor(query);
    final currentProjection = identical(
      projection?.generation,
      account.metadataGeneration,
    );
    account.touch(query);
    if (account.requests.containsKey(query) ||
        (!refresh && !more && held.loaded && currentProjection) ||
        (more && (!held.loaded || (!held.hasMore && currentProjection)))) {
      return;
    }

    final rowsGeneration =
        projection?.rowsGeneration ?? account.metadataGeneration;
    if (refresh) account.refreshMetadata();
    final token = Object();
    final lease = account.lease;
    account.requests[query] = token;
    account.states[query] = _DirectoryProjection(
      UserDirectoryState(
        items: held.items,
        columns: held.columns,
        availableColumns: held.availableColumns,
        groupNames: held.groupNames,
        canManageColumns: held.canManageColumns,
        totalRows: held.totalRows,
        nextPage: held.nextPage,
        lastUpdatedAt: held.lastUpdatedAt,
        hasMore: held.hasMore,
        loading: !more,
        loadingMore: more,
        loaded: held.loaded,
      ),
      account.metadataGeneration,
      rowsGeneration: rowsGeneration,
    );
    account.trim();
    notifySafely();

    try {
      AccountRequestCredentials? credentialsSnapshot;
      while (_isCurrent(instance.url, account, query, token)) {
        final generation = account.metadataGeneration;
        final append = more && identical(rowsGeneration, generation);
        try {
          final auth = credentialsSnapshot ??= await _credentialsFor(
            instance,
            account,
            query,
            token,
          );
          if (auth == null ||
              !_isCurrent(instance.url, account, query, token)) {
            return;
          }
          if (!identical(account.metadataGeneration, generation)) continue;
          final metadata = await _ensureMetadata(
            instance,
            auth,
            account,
            generation,
          );
          if (!_isCurrent(instance.url, account, query, token)) return;
          if (!identical(account.metadataGeneration, generation)) continue;
          final requestedPage = append ? held.nextPage : 0;
          final page = await auth.run(
            () => api.directory(
              siteUrl: instance.url,
              apiKey: auth.apiKey,
              clientId: auth.apiKey == null ? null : auth.clientId,
              period: query.period,
              columns: metadata.columns,
              page: requestedPage,
              order: query.order,
              ascending: query.ascending,
              name: query.search,
              group: query.group,
            ),
          );
          if (!_isCurrent(instance.url, account, query, token)) return;
          if (!identical(account.metadataGeneration, generation)) continue;
          lease.commit(() {
            if (!_isCurrent(instance.url, account, query, token)) return;
            if (!identical(account.metadataGeneration, generation)) return;
            final rows = append ? [...held.items] : <UserDirectoryItem>[];
            final seen = {for (final row in rows) row.id};
            for (final row in page.items) {
              if (seen.add(row.id)) rows.add(row);
            }
            account.states[query] = _DirectoryProjection(
              UserDirectoryState(
                items: rows,
                columns: metadata.columns,
                availableColumns: metadata.availableColumns,
                groupNames: metadata.groupNames,
                canManageColumns: metadata.canManageColumns,
                totalRows: page.totalRows,
                nextPage: requestedPage + 1,
                lastUpdatedAt: page.lastUpdatedAt,
                hasMore:
                    page.nextPagePath != null &&
                    page.items.isNotEmpty &&
                    rows.length < page.totalRows &&
                    requestedPage < UserDirectoryApi.maximumPage,
                loaded: true,
              ),
              generation,
              rowsGeneration: generation,
            );
            notifySafely();
          });
          return;
        } catch (error) {
          if (!_isCurrent(instance.url, account, query, token)) return;
          if (!identical(account.metadataGeneration, generation)) continue;
          lease.commit(() {
            if (!_isCurrent(instance.url, account, query, token)) return;
            if (!identical(account.metadataGeneration, generation)) return;
            account.states[query] = _DirectoryProjection(
              UserDirectoryState(
                items: held.items,
                columns: held.columns,
                availableColumns: held.availableColumns,
                groupNames: held.groupNames,
                canManageColumns: held.canManageColumns,
                totalRows: held.totalRows,
                nextPage: held.nextPage,
                lastUpdatedAt: held.lastUpdatedAt,
                hasMore: held.hasMore,
                loaded: true,
                error: append
                    ? appL10n.couldnTLoadMoreUsers
                    : appL10n.couldnTLoadTheUserDirectory,
                pageError: append,
              ),
              generation,
              rowsGeneration: rowsGeneration,
            );
            notifySafely();
          });
          return;
        }
      }
    } finally {
      if (identical(account.requests[query], token)) {
        account.requests.remove(query);
      }
    }
  }

  Future<bool> updateColumns(
    DiscourseInstance instance,
    List<UserDirectoryColumn> columns, {
    required UserDirectoryQuery query,
  }) async {
    if (isDisposed || instance.user?.staff != true) return false;
    final account = _ensureAccount(instance.url);
    if (account.columnUpdate != null) return false;
    final token = Object();
    final lease = account.lease;
    account.columnUpdate = token;
    notifySafely();
    bool isCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_accounts[instance.url], account) &&
        identical(account.columnUpdate, token);

    try {
      final auth = await AccountRequestSession(
        instance.url,
        lease,
      ).credentials(credentials);
      final apiKey = auth.apiKey;
      if (!isCurrent() || apiKey == null) return false;
      final clientId = auth.clientId;
      if (!isCurrent()) return false;
      await auth.run(
        () => api.updateColumns(
          siteUrl: instance.url,
          apiKey: apiKey,
          clientId: clientId,
          columns: columns,
        ),
      );
      if (!isCurrent()) return false;

      account.clearQueries();
      notifySafely();
      if (!isCurrent()) return false;
      await load(instance, query: query, refresh: true);
      return isCurrent();
    } catch (error) {
      return false;
    } finally {
      if (isCurrent()) {
        account.columnUpdate = null;
        notifySafely();
      }
    }
  }

  Future<UserDirectoryMetadata> _ensureMetadata(
    DiscourseInstance instance,
    AccountRequestCredentials auth,
    _DirectoryAccount account,
    Object generation,
  ) async {
    final cached = account.metadata;
    if (cached != null) return cached;
    final existing = account.metadataLoad;
    if (existing != null) return existing;
    final future = auth.run(
      () => api.metadata(
        siteUrl: instance.url,
        apiKey: auth.apiKey,
        clientId: auth.apiKey == null ? null : auth.clientId,
        canManageColumns: instance.user?.staff == true,
      ),
    );
    if (identical(account.metadataGeneration, generation)) {
      account.metadataLoad = future;
    }
    try {
      final loaded = await future;
      if (!isDisposed &&
          account.lease.isCurrent &&
          identical(_accounts[instance.url], account) &&
          identical(account.metadataGeneration, generation) &&
          identical(account.metadataLoad, future)) {
        account.metadata = loaded;
      }
      return loaded;
    } finally {
      if (identical(account.metadataLoad, future)) {
        account.metadataLoad = null;
      }
    }
  }

  Future<AccountRequestCredentials?> _credentialsFor(
    DiscourseInstance instance,
    _DirectoryAccount account,
    UserDirectoryQuery query,
    Object token,
  ) async {
    if (!_isCurrent(instance.url, account, query, token)) return null;
    final session = AccountRequestSession(instance.url, account.lease);
    final auth = instance.isConnected
        ? await session.credentials(credentials)
        : session.anonymousCredentials();
    return _isCurrent(instance.url, account, query, token) ? auth : null;
  }

  bool _isCurrent(
    String siteUrl,
    _DirectoryAccount account,
    UserDirectoryQuery query,
    Object token,
  ) =>
      !isDisposed &&
      account.lease.isCurrent &&
      identical(_accounts[siteUrl], account) &&
      identical(account.requests[query], token);

  void forget(String siteUrl) {
    _accounts.remove(siteUrl)?.dispose();
    notifySafely();
  }

  @override
  void dispose() {
    for (final account in _accounts.values) {
      account.dispose();
    }
    _accounts.clear();
    super.dispose();
  }
}
