import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/site_lifecycle.dart';
import '../data/user_directory_api.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/user_directory.dart';

@immutable
final class UserDirectoryQuery {
  const UserDirectoryQuery({
    this.period = UserDirectoryPeriod.weekly,
    this.search = '',
    this.group,
    this.order = 'likes_received',
    this.ascending = false,
  });

  final UserDirectoryPeriod period;
  final String search;
  final String? group;
  final String order;
  final bool ascending;

  UserDirectoryQuery copyWith({
    UserDirectoryPeriod? period,
    String? search,
    Object? group = _absent,
    String? order,
    bool? ascending,
  }) => UserDirectoryQuery(
    period: period ?? this.period,
    search: search ?? this.search,
    group: identical(group, _absent) ? this.group : group as String?,
    order: order ?? this.order,
    ascending: ascending ?? this.ascending,
  );

  UserDirectoryQuery withoutGroup() => copyWith(group: null);

  @override
  bool operator ==(Object other) =>
      other is UserDirectoryQuery &&
      other.period == period &&
      other.search == search &&
      other.group == group &&
      other.order == order &&
      other.ascending == ascending;

  @override
  int get hashCode => Object.hash(period, search, group, order, ascending);
}

const Object _absent = Object();

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

typedef _DirectoryKey = ({String siteUrl, UserDirectoryQuery query});
typedef _DirectoryCredentials = ({String? apiKey, String? clientId});

final class UserDirectoryController extends FrameSafeNotifier {
  UserDirectoryController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final UserDirectoryApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;

  final Map<_DirectoryKey, UserDirectoryState> _states = {};
  final Map<String, UserDirectoryQuery> _queries = {};
  final Map<String, UserDirectoryMetadata> _metadata = {};
  final Map<String, Future<UserDirectoryMetadata>> _metadataLoads = {};
  final Map<_DirectoryKey, Object> _requests = {};
  final Map<_DirectoryKey, SiteLease> _leases = {};
  final Map<String, Object> _columnUpdates = {};

  UserDirectoryQuery queryFor(String siteUrl) =>
      _queries[siteUrl] ?? const UserDirectoryQuery();

  UserDirectoryState stateFor(String siteUrl, [UserDirectoryQuery? query]) {
    final resolved = query ?? queryFor(siteUrl);
    final held = _states[(siteUrl: siteUrl, query: resolved)];
    if (held != null) return held;
    final metadata = _metadata[siteUrl];
    return metadata == null
        ? const UserDirectoryState.empty()
        : UserDirectoryState(
            columns: metadata.columns,
            availableColumns: metadata.availableColumns,
            groupNames: metadata.groupNames,
            canManageColumns: metadata.canManageColumns,
          );
  }

  bool updatingColumnsFor(String siteUrl) =>
      _columnUpdates.containsKey(siteUrl);

  bool replaceQuery(String siteUrl, UserDirectoryQuery query) {
    final normalized = query.copyWith(
      search: query.search.trim(),
      group: query.group?.trim().isEmpty == true ? null : query.group?.trim(),
      order: query.order.trim(),
    );
    if (queryFor(siteUrl) == normalized) return false;
    _queries[siteUrl] = normalized;
    notifySafely();
    return true;
  }

  Future<void> load(
    DiscourseInstance instance, {
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed) return;
    final query = queryFor(instance.url);
    final key = (siteUrl: instance.url, query: query);
    final held = stateFor(instance.url, query);
    if (_requests.containsKey(key) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }

    final token = Object();
    final lease = lifecycle.capture(instance.url);
    _requests[key] = token;
    _leases[key] = lease;
    _states[key] = UserDirectoryState(
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
    );
    notifySafely();

    try {
      final auth = await _credentialsFor(instance, key, token, lease);
      if (auth == null) return;
      final metadata = await _ensureMetadata(instance, auth, lease);
      if (!_isCurrent(key, token, lease)) return;
      final page = await api.directory(
        siteUrl: instance.url,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
        period: query.period,
        columns: metadata.columns,
        page: more ? held.nextPage : 0,
        order: query.order,
        ascending: query.ascending,
        name: query.search,
        group: query.group,
      );
      if (!_isCurrent(key, token, lease)) return;
      lease.commit(() {
        if (!_isCurrent(key, token, lease)) return;
        final requestedPage = more ? held.nextPage : 0;
        final current = _states[key] ?? held;
        final rows = more ? [...current.items] : <UserDirectoryItem>[];
        final seen = {for (final row in rows) row.id};
        for (final row in page.items) {
          if (seen.add(row.id)) rows.add(row);
        }
        _states[key] = UserDirectoryState(
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
        );
        notifySafely();
      });
    } catch (error, stackTrace) {
      if (!_isCurrent(key, token, lease)) return;
      DiagnosticsSink.current.reportError(
        error,
        stackTrace,
        operation: 'users.directory',
        source: 'users-directory',
        handled: true,
        degraded: true,
      );
      lease.commit(() {
        if (!_isCurrent(key, token, lease)) return;
        final current = _states[key] ?? held;
        _states[key] = UserDirectoryState(
          items: current.items,
          columns: current.columns,
          availableColumns: current.availableColumns,
          groupNames: current.groupNames,
          canManageColumns: current.canManageColumns,
          totalRows: current.totalRows,
          nextPage: current.nextPage,
          lastUpdatedAt: current.lastUpdatedAt,
          hasMore: current.hasMore,
          loaded: true,
          error: more
              ? "Couldn't load more users."
              : "Couldn't load the user directory.",
          pageError: more,
        );
        notifySafely();
      });
    } finally {
      if (identical(_requests[key], token)) {
        _requests.remove(key);
        _leases.remove(key);
      }
    }
  }

  Future<bool> updateColumns(
    DiscourseInstance instance,
    List<UserDirectoryColumn> columns,
  ) async {
    if (isDisposed ||
        instance.user?.staff != true ||
        _columnUpdates.containsKey(instance.url)) {
      return false;
    }
    final token = Object();
    final lease = lifecycle.capture(instance.url);
    _columnUpdates[instance.url] = token;
    notifySafely();
    bool isCurrent() =>
        !isDisposed &&
        lease.isCurrent &&
        identical(_columnUpdates[instance.url], token);

    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (!isCurrent() || apiKey == null) return false;
      final clientId = await credentials.clientId();
      if (!isCurrent()) return false;
      await api.updateColumns(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        columns: columns,
      );
      if (!isCurrent()) return false;

      _metadata.remove(instance.url);
      _metadataLoads.remove(instance.url)?.ignore();
      // Every query was decoded against the previous column configuration.
      // Retain only the visible rows while refreshing them, so returning to
      // another filter cannot revive its old columns or plugin field values.
      final currentQuery = queryFor(instance.url);
      _states.removeWhere(
        (key, _) => key.siteUrl == instance.url && key.query != currentQuery,
      );
      _requests.removeWhere((key, _) => key.siteUrl == instance.url);
      _leases.removeWhere((key, _) => key.siteUrl == instance.url);
      await load(instance, refresh: true);
      return isCurrent();
    } catch (error, stackTrace) {
      if (isCurrent()) {
        DiagnosticsSink.current.reportError(
          error,
          stackTrace,
          operation: 'users.directory.columns.update',
          source: 'users-directory',
          handled: true,
          degraded: true,
        );
      }
      return false;
    } finally {
      if (!isDisposed && identical(_columnUpdates[instance.url], token)) {
        _columnUpdates.remove(instance.url);
        notifySafely();
      }
    }
  }

  Future<UserDirectoryMetadata> _ensureMetadata(
    DiscourseInstance instance,
    _DirectoryCredentials auth,
    SiteLease lease,
  ) async {
    final cached = _metadata[instance.url];
    if (cached != null) return cached;
    final existing = _metadataLoads[instance.url];
    if (existing != null) return existing;
    final future = api.metadata(
      siteUrl: instance.url,
      apiKey: auth.apiKey,
      clientId: auth.clientId,
      fallbackGroupNames: instance.user?.groups ?? const [],
      canManageColumns: instance.user?.staff == true,
    );
    _metadataLoads[instance.url] = future;
    try {
      final loaded = await future;
      if (!isDisposed &&
          lease.isCurrent &&
          identical(_metadataLoads[instance.url], future)) {
        _metadata[instance.url] = loaded;
      }
      return loaded;
    } finally {
      if (identical(_metadataLoads[instance.url], future)) {
        _metadataLoads.remove(instance.url)?.ignore();
      }
    }
  }

  Future<_DirectoryCredentials?> _credentialsFor(
    DiscourseInstance instance,
    _DirectoryKey key,
    Object token,
    SiteLease lease,
  ) async {
    if (!instance.isConnected) {
      return _isCurrent(key, token, lease)
          ? (apiKey: null, clientId: null)
          : null;
    }
    final apiKey = await credentials.apiKeyFor(instance.url);
    if (!_isCurrent(key, token, lease)) return null;
    if (apiKey == null) return (apiKey: null, clientId: null);
    final clientId = await credentials.clientId();
    return _isCurrent(key, token, lease)
        ? (apiKey: apiKey, clientId: clientId)
        : null;
  }

  bool _isCurrent(_DirectoryKey key, Object token, SiteLease lease) =>
      !isDisposed &&
      lease.isCurrent &&
      identical(_requests[key], token) &&
      identical(_leases[key], lease);

  void forget(String siteUrl) {
    _states.removeWhere((key, _) => key.siteUrl == siteUrl);
    _queries.remove(siteUrl);
    _metadata.remove(siteUrl);
    _metadataLoads.remove(siteUrl)?.ignore();
    _requests.removeWhere((key, _) => key.siteUrl == siteUrl);
    _leases.removeWhere((key, _) => key.siteUrl == siteUrl);
    _columnUpdates.remove(siteUrl);
    notifySafely();
  }

  @override
  void dispose() {
    _states.clear();
    _queries.clear();
    _metadata.clear();
    _metadataLoads.clear();
    _requests.clear();
    _leases.clear();
    _columnUpdates.clear();
    super.dispose();
  }
}
