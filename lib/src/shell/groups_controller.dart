import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

import '../data/account_request_session.dart';
import '../data/api_credentials.dart';
import '../data/discourse_api_contracts.dart';
import '../data/groups_api.dart';
import '../data/site_lifecycle.dart';

import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/group.dart';
import 'group_write.dart';

export 'group_write.dart';

@immutable
final class GroupDirectoryQuery {
  const GroupDirectoryQuery({this.filter = '', this.type, this.username});

  final String filter;
  final String? type;
  final String? username;

  GroupDirectoryQuery copyWith({
    String? filter,
    Object? type = _absent,
    Object? username = _absent,
  }) => GroupDirectoryQuery(
    filter: filter ?? this.filter,
    type: identical(type, _absent) ? this.type : type as String?,
    username: identical(username, _absent)
        ? this.username
        : username as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is GroupDirectoryQuery &&
      other.filter == filter &&
      other.type == type &&
      other.username == username;

  @override
  int get hashCode => Object.hash(filter, type, username);
}

const Object _absent = Object();

String get _saveFailureMessage => appL10n.couldnTSaveThatGroupChange;

List<T> _immutableSnapshot<T>(List<T> values) =>
    values.isEmpty ? const [] : List<T>.unmodifiable(values);

@immutable
final class GroupDirectoryState {
  factory GroupDirectoryState({
    List<Group> groups = const [],
    List<String> typeFilters = const [],
    int totalRows = 0,
    int nextPage = 0,
    bool hasMore = false,
    bool loading = false,
    bool loadingMore = false,
    bool loaded = false,
    String? error,
    bool pageError = false,
  }) => GroupDirectoryState._(
    groups: _immutableSnapshot(groups),
    typeFilters: _immutableSnapshot(typeFilters),
    totalRows: totalRows,
    nextPage: nextPage,
    hasMore: hasMore,
    loading: loading,
    loadingMore: loadingMore,
    loaded: loaded,
    error: error,
    pageError: pageError,
  );

  const GroupDirectoryState.empty() : this._();

  const GroupDirectoryState._({
    this.groups = const [],
    this.typeFilters = const [],
    this.totalRows = 0,
    this.nextPage = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.pageError = false,
  });

  final List<Group> groups;
  final List<String> typeFilters;
  final int totalRows;
  final int nextPage;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final bool pageError;
}

@immutable
final class GroupDetailState {
  const GroupDetailState({
    this.detail,
    this.loading = false,
    this.loaded = false,
    this.mutating = false,
    this.error,
  });

  final GroupDetail? detail;
  final bool loading;
  final bool loaded;
  final bool mutating;
  final String? error;
}

@immutable
final class GroupMembersState {
  factory GroupMembersState({
    List<GroupMember> members = const [],
    int total = 0,
    int nextOffset = 0,
    bool hasMore = false,
    bool loading = false,
    bool loadingMore = false,
    bool loaded = false,
    String? error,
    bool pageError = false,
  }) => GroupMembersState._(
    members: _immutableSnapshot(members),
    total: total,
    nextOffset: nextOffset,
    hasMore: hasMore,
    loading: loading,
    loadingMore: loadingMore,
    loaded: loaded,
    error: error,
    pageError: pageError,
  );

  const GroupMembersState.empty() : this._();

  const GroupMembersState._({
    this.members = const [],
    this.total = 0,
    this.nextOffset = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.pageError = false,
  });

  final List<GroupMember> members;
  final int total;
  final int nextOffset;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final bool pageError;
}

@immutable
final class GroupRequestersState {
  factory GroupRequestersState({
    List<GroupRequester> requesters = const [],
    int total = 0,
    int nextOffset = 0,
    bool hasMore = false,
    bool loading = false,
    bool loadingMore = false,
    bool loaded = false,
    String? error,
    bool pageError = false,
  }) => GroupRequestersState._(
    requesters: _immutableSnapshot(requesters),
    total: total,
    nextOffset: nextOffset,
    hasMore: hasMore,
    loading: loading,
    loadingMore: loadingMore,
    loaded: loaded,
    error: error,
    pageError: pageError,
  );

  const GroupRequestersState.empty() : this._();

  const GroupRequestersState._({
    this.requesters = const [],
    this.total = 0,
    this.nextOffset = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.pageError = false,
  });

  final List<GroupRequester> requesters;
  final int total;
  final int nextOffset;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final bool pageError;
}

@immutable
final class GroupActivityState {
  factory GroupActivityState({
    List<GroupActivityPost> posts = const [],
    bool hasMore = false,
    bool loading = false,
    bool loadingMore = false,
    bool loaded = false,
    String? error,
    bool pageError = false,
  }) => GroupActivityState._(
    posts: _immutableSnapshot(posts),
    hasMore: hasMore,
    loading: loading,
    loadingMore: loadingMore,
    loaded: loaded,
    error: error,
    pageError: pageError,
  );

  const GroupActivityState.empty() : this._();

  const GroupActivityState._({
    this.posts = const [],
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.pageError = false,
  });

  final List<GroupActivityPost> posts;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final bool pageError;
}

@immutable
final class GroupPermissionsState {
  factory GroupPermissionsState({
    List<GroupPermission> permissions = const [],
    bool loading = false,
    bool loaded = false,
    String? error,
  }) => GroupPermissionsState._(
    permissions: _immutableSnapshot(permissions),
    loading: loading,
    loaded: loaded,
    error: error,
  );

  const GroupPermissionsState.empty() : this._();

  const GroupPermissionsState._({
    this.permissions = const [],
    this.loading = false,
    this.loaded = false,
    this.error,
  });

  final List<GroupPermission> permissions;
  final bool loading;
  final bool loaded;
  final String? error;
}

@immutable
final class GroupLogsState {
  factory GroupLogsState({
    List<GroupLogEntry> logs = const [],
    int nextPage = 0,
    bool hasMore = false,
    bool loading = false,
    bool loadingMore = false,
    bool loaded = false,
    String? error,
    bool pageError = false,
  }) => GroupLogsState._(
    logs: _immutableSnapshot(logs),
    nextPage: nextPage,
    hasMore: hasMore,
    loading: loading,
    loadingMore: loadingMore,
    loaded: loaded,
    error: error,
    pageError: pageError,
  );

  const GroupLogsState.empty() : this._();

  const GroupLogsState._({
    this.logs = const [],
    this.nextPage = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.pageError = false,
  });

  final List<GroupLogEntry> logs;
  final int nextPage;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final String? error;
  final bool pageError;
}

final class _GroupUpdateAttempt {
  const _GroupUpdateAttempt(
    this.instance,
    this.group,
    this.command,
    this.lease,
  );

  final DiscourseInstance instance;
  final Group group;
  final GroupUpdateCommand command;
  final SiteLease lease;
}

typedef _DirectoryKey = ({String siteUrl, GroupDirectoryQuery query});
typedef _GroupKey = ({String siteUrl, String groupName});
typedef _MemberListKey = ({
  String siteUrl,
  String groupName,
  String filter,
  String? order,
  bool ascending,
});
typedef _FilterListKey = ({String siteUrl, String groupName, String filter});
typedef _ActivityKey = ({String siteUrl, String groupName, bool mentions});

final class _GroupRequest {
  _GroupRequest({
    required this.key,
    required this.siteUrl,
    required this.lease,
    this.groupName,
  });

  final Object key;
  final String siteUrl;
  final SiteLease lease;
  final String? groupName;
  final Map<int, Group> directoryReplacements = {};
}

final class _GroupMutation {
  _GroupMutation({required bool removesRows})
    : removal = removesRows ? Completer<void>() : null;

  final Completer<void>? removal;

  void finishRemoval() {
    final pending = removal;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}

final class GroupsController extends FrameSafeNotifier {
  GroupsController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  static const int _cachedQueriesPerSite = 16;

  final GroupsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;

  final Map<_DirectoryKey, GroupDirectoryState> _directories = {};
  final Map<_GroupKey, GroupDetailState> _details = {};
  final Map<_GroupKey, _GroupUpdateAttempt> _pendingUpdates = {};
  final Map<_GroupKey, Group> _unreconciledUpdates = {};
  final Expando<_GroupUpdateAttempt> _confirmationAttempts = Expando();
  final Map<_MemberListKey, GroupMembersState> _members = {};
  final Map<_FilterListKey, GroupRequestersState> _requesters = {};
  final Map<_ActivityKey, GroupActivityState> _activities = {};
  final Map<_GroupKey, GroupPermissionsState> _permissions = {};
  final Map<_GroupKey, GroupLogsState> _logs = {};
  final Map<String, GroupDirectoryQuery> _presentedDirectoryQueries = {};
  final Map<Object, _GroupRequest> _requests = {};
  final Map<_GroupKey, _GroupMutation> _mutations = {};

  GroupDirectoryState directoryState(
    String siteUrl,
    GroupDirectoryQuery query,
  ) =>
      _directories[(siteUrl: siteUrl, query: query)] ??
      const GroupDirectoryState.empty();

  GroupDirectoryState? presentedDirectoryState(String siteUrl) {
    final query = _presentedDirectoryQueries[siteUrl];
    return query == null ? null : directoryState(siteUrl, query);
  }

  GroupDetailState detailState(String siteUrl, String groupName) =>
      _details[_groupKey(siteUrl, groupName)] ?? const GroupDetailState();

  GroupMembersState membersState(
    String siteUrl,
    String groupName, {
    String filter = '',
    String? order,
    bool ascending = true,
  }) =>
      _members[_memberListKey(siteUrl, groupName, filter, order, ascending)] ??
      const GroupMembersState.empty();

  GroupRequestersState requestersState(
    String siteUrl,
    String groupName, {
    String filter = '',
  }) =>
      _requesters[_filterListKey(siteUrl, groupName, filter)] ??
      const GroupRequestersState.empty();

  GroupActivityState activityState(
    String siteUrl,
    String groupName, {
    required bool mentions,
  }) =>
      _activities[(
        siteUrl: siteUrl,
        groupName: _normalize(groupName),
        mentions: mentions,
      )] ??
      const GroupActivityState.empty();

  GroupPermissionsState permissionsState(String siteUrl, String groupName) =>
      _permissions[_groupKey(siteUrl, groupName)] ??
      const GroupPermissionsState.empty();

  GroupLogsState logsState(String siteUrl, String groupName) =>
      _logs[_groupKey(siteUrl, groupName)] ?? const GroupLogsState.empty();

  Future<void> loadDirectory(
    DiscourseInstance instance,
    GroupDirectoryQuery query, {
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed) return;
    final key = (siteUrl: instance.url, query: query);
    _touchQuery(_directories, key);
    final held = directoryState(instance.url, query);
    final presentedChanged = _presentedDirectoryQueries[instance.url] != query;
    _presentedDirectoryQueries[instance.url] = query;
    if (_requests.containsKey(key) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      if (presentedChanged) notifySafely();
      return;
    }
    final token = _start(key, instance.url);
    _directories[key] = GroupDirectoryState._(
      groups: held.groups,
      typeFilters: held.typeFilters,
      totalRows: held.totalRows,
      nextPage: held.nextPage,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    _trimQueries(_directories, instance.url, siteOf: (key) => key.siteUrl);
    notifySafely();
    if (!_current(token)) return;
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null || !_current(token)) return;
      final page = await auth.run(
        () => api.directory(
          siteUrl: instance.url,
          apiKey: auth.apiKey,
          clientId: auth.apiKey == null ? null : auth.clientId,
          page: more ? held.nextPage : 0,
          filter: query.filter,
          type: query.type,
          username: query.username,
        ),
      );
      _commit(token, () {
        // An entry absent here was dropped by a deletion; the page predates
        // that and must not bring the entry back.
        final current = _directories[key];
        if (current == null) return;
        final rows = more ? [...current.groups] : <Group>[];
        final seen = {for (final group in rows) group.id};
        for (final returned in page.groups) {
          final group = token.directoryReplacements[returned.id] ?? returned;
          if (seen.add(group.id)) rows.add(group);
        }
        _directories[key] = GroupDirectoryState(
          groups: List.unmodifiable(rows),
          typeFilters: page.typeFilters,
          totalRows: page.totalRows,
          nextPage: (more ? held.nextPage : 0) + 1,
          // Discourse includes a next-page URL even after the final group.
          hasMore:
              page.nextPagePath != null &&
              page.groups.isNotEmpty &&
              rows.length < page.totalRows,
          loaded: true,
        );
      });
    } catch (error) {
      _fail(token, () {
        // The failure keeps whatever the list holds now, for the same reason
        // the commit does: a mutation may have changed it since the request.
        final current = _directories[key];
        if (current == null) return;
        _directories[key] = GroupDirectoryState._(
          groups: current.groups,
          typeFilters: current.typeFilters,
          totalRows: current.totalRows,
          nextPage: current.nextPage,
          hasMore: current.hasMore,
          loaded: true,
          error: more
              ? appL10n.couldnTLoadMoreGroups
              : appL10n.couldnTLoadTheGroupDirectory,
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
  }

  /// A small directory preview, kept separate from paginated member lists.
  Future<List<GroupMember>> loadMemberPreview(
    DiscourseInstance instance,
    Group group,
  ) async {
    if (isDisposed || !group.canSeeMembers || group.userCount == 0) {
      return const [];
    }
    final token = _start(Object(), instance.url, groupName: group.name);
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null || !_current(token)) return const [];
      final page = await auth.run(
        () => api.members(
          siteUrl: instance.url,
          groupName: group.name,
          apiKey: auth.apiKey,
          clientId: auth.apiKey == null ? null : auth.clientId,
          limit: 4,
        ),
      );
      return _current(token)
          ? List.unmodifiable(page.members.take(4))
          : const [];
    } catch (error) {
      return const [];
    } finally {
      _finish(token);
    }
  }

  Future<bool> loadDetail(
    DiscourseInstance instance,
    String groupName, {
    bool refresh = false,
    void Function(Group group)? onReconciled,
  }) async {
    if (isDisposed) return false;
    final key = _groupKey(instance.url, groupName);
    _touchQuery(_details, key);
    final held = detailState(instance.url, groupName);
    final pendingUpdate = _unreconciledUpdates[key];
    if (_requests.containsKey(key) ||
        (!refresh && held.loaded && pendingUpdate == null)) {
      return false;
    }
    final token = _start(key, instance.url, groupName: groupName);
    _details[key] = GroupDetailState(
      detail: held.detail,
      loading: true,
      loaded: held.loaded,
      mutating: held.mutating,
    );
    _trimQueries(
      _details,
      instance.url,
      siteOf: (key) => key.siteUrl,
      // A write in flight owns this entry's mutating flag and writes the entry
      // back when it settles; evicting it would show the group idle mid-write
      // and re-add the entry outside this bound.
      pinned: _mutations.containsKey,
    );
    notifySafely();
    var committed = false;
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null || !_current(token)) return false;
      final detail = await auth.run(
        () => pendingUpdate == null
            ? api.detail(
                siteUrl: instance.url,
                groupName: groupName,
                apiKey: auth.apiKey,
                clientId: auth.apiKey == null ? null : auth.clientId,
              )
            : api.detailById(
                siteUrl: instance.url,
                groupId: pendingUpdate.id,
                apiKey: auth.apiKey,
                clientId: auth.apiKey == null ? null : auth.clientId,
              ),
      );
      _commit(token, () {
        if (pendingUpdate != null) {
          _unreconciledUpdates.remove(key);
          _projectUpdatedGroup(instance.url, pendingUpdate, detail.group);
        } else {
          _projectDirectoryGroup(instance.url, detail.group);
        }
        final detailKey = pendingUpdate == null
            ? key
            : _groupKey(instance.url, detail.group.name);
        _details[detailKey] = GroupDetailState(detail: detail, loaded: true);
        committed = true;
        if (pendingUpdate != null) onReconciled?.call(detail.group);
      });
    } catch (error) {
      _fail(token, () {
        _details[key] = GroupDetailState(
          detail:
              pendingUpdate != null &&
                  error is SiteLookupException &&
                  error.statusCode == 404
              ? null
              : held.detail,
          loaded: true,
          error: appL10n.couldnTLoadThisGroup,
        );
      });
    } finally {
      _finish(token);
    }
    return committed;
  }

  Future<bool> loadMembers(
    DiscourseInstance instance,
    String groupName, {
    String filter = '',
    String? order,
    bool ascending = true,
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed) return false;
    final key = _memberListKey(
      instance.url,
      groupName,
      filter,
      order,
      ascending,
    );
    _touchQuery(_members, key);
    final held = membersState(
      instance.url,
      groupName,
      filter: filter,
      order: order,
      ascending: ascending,
    );
    // A refresh supersedes a page already in flight for this list. It is
    // issued after a confirmed mutation such as adding members, so dropping
    // it would hide that mutation until the next visit; the older page's
    // commit is dropped by its token instead.
    if ((_requests.containsKey(key) && !refresh) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return false;
    }
    final token = _start(key, instance.url, groupName: groupName);
    _members[key] = GroupMembersState._(
      members: held.members,
      total: held.total,
      nextOffset: held.nextOffset,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    _trimQueries(_members, instance.url, siteOf: (key) => key.siteUrl);
    notifySafely();
    var committed = false;
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null || !_current(token)) return false;
      var base = held;
      while (_current(token)) {
        final page = await auth.run(
          () => api.members(
            siteUrl: instance.url,
            groupName: groupName,
            apiKey: auth.apiKey,
            clientId: auth.apiKey == null ? null : auth.clientId,
            offset: more ? base.nextOffset : 0,
            order: order,
            ascending: ascending,
            filter: filter,
          ),
        );
        // The server can apply a deletion before its write response arrives.
        // Settle its cache update before deciding whether this page is usable.
        final removal = _mutations[_groupKey(instance.url, groupName)]?.removal;
        if (removal != null) await removal.future;
        final current = _members[key];
        if (!_current(token) || current == null) return false;
        if (_removedDuringLoad(
          base.members,
          current.members,
          (member) => member.id,
        ).isNotEmpty) {
          // The server may have sampled this page before or after the removal.
          // Retry its corrected window: guessing a shift can skip a boundary
          // row or resurrect a deleted row. Keep the visible prefix meanwhile.
          base = current;
          continue;
        }
        _commit(token, () {
          committed = true;
          final rows = more ? [...current.members] : <GroupMember>[];
          final seen = {for (final member in rows) member.id};
          for (final member in page.members) {
            if (seen.add(member.id)) rows.add(member);
          }
          _members[key] = GroupMembersState(
            members: List.unmodifiable(rows),
            total: page.total,
            nextOffset: page.nextOffset,
            hasMore:
                page.hasMore && page.nextOffset > (more ? base.nextOffset : 0),
            loaded: true,
          );
        });
        return committed;
      }
    } catch (error) {
      _fail(token, () {
        final current = _members[key];
        if (current == null) return;
        _members[key] = GroupMembersState._(
          members: current.members,
          total: current.total,
          nextOffset: current.nextOffset,
          hasMore: current.hasMore,
          loaded: true,
          error: more
              ? appL10n.couldnTLoadMoreMembers
              : appL10n.couldnTLoadGroupMembers,
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
    return committed;
  }

  Future<void> loadRequesters(
    DiscourseInstance instance,
    String groupName, {
    String filter = '',
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed) return;
    final key = _filterListKey(instance.url, groupName, filter);
    _touchQuery(_requesters, key);
    final held = requestersState(instance.url, groupName, filter: filter);
    if (_requests.containsKey(('requesters', key)) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }
    final requestKey = ('requesters', key);
    final token = _start(requestKey, instance.url, groupName: groupName);
    _requesters[key] = GroupRequestersState._(
      requesters: held.requesters,
      total: held.total,
      nextOffset: held.nextOffset,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    _trimQueries(
      _requesters,
      instance.url,
      siteOf: (key) => key.siteUrl,
      requestKeyOf: (key) => ('requesters', key),
    );
    notifySafely();
    try {
      final auth = await _requiredCredentials(instance, token);
      if (auth == null || !_current(token)) return;
      var base = held;
      while (_current(token)) {
        final page = await auth.run(
          () => api.requesters(
            siteUrl: instance.url,
            apiKey: auth.apiKey!,
            clientId: auth.apiKey == null ? null : auth.clientId,
            groupName: groupName,
            offset: more ? base.nextOffset : 0,
            filter: filter,
          ),
        );
        final removal = _mutations[_groupKey(instance.url, groupName)]?.removal;
        if (removal != null) await removal.future;
        final current = _requesters[key];
        if (!_current(token) || current == null) return;
        if (_removedDuringLoad(
          base.requesters,
          current.requesters,
          (requester) => requester.id,
        ).isNotEmpty) {
          // As with members, only a new read can disambiguate the page's offset
          // and total after a removal. Multiple removals share this one retry.
          base = current;
          continue;
        }
        _commit(token, () {
          final rows = more ? [...current.requesters] : <GroupRequester>[];
          final seen = {for (final requester in rows) requester.id};
          for (final requester in page.requesters) {
            if (seen.add(requester.id)) rows.add(requester);
          }
          _requesters[key] = GroupRequestersState(
            requesters: List.unmodifiable(rows),
            total: page.total,
            nextOffset: page.nextOffset,
            hasMore:
                page.hasMore && page.nextOffset > (more ? base.nextOffset : 0),
            loaded: true,
          );
        });
        return;
      }
    } catch (error) {
      _fail(token, () {
        final current = _requesters[key];
        if (current == null) return;
        _requesters[key] = GroupRequestersState._(
          requesters: current.requesters,
          total: current.total,
          nextOffset: current.nextOffset,
          hasMore: current.hasMore,
          loaded: true,
          error: more
              ? appL10n.couldnTLoadMoreRequests
              : appL10n.couldnTLoadMembershipRequests,
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<void> loadActivity(
    DiscourseInstance instance,
    String groupName, {
    required bool mentions,
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed) return;
    final key = (
      siteUrl: instance.url,
      groupName: _normalize(groupName),
      mentions: mentions,
    );
    _touchQuery(_activities, key);
    final held = activityState(instance.url, groupName, mentions: mentions);
    if (_requests.containsKey(key) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }
    final token = _start(key, instance.url, groupName: groupName);
    _activities[key] = GroupActivityState._(
      posts: held.posts,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    _trimQueries(_activities, instance.url, siteOf: (key) => key.siteUrl);
    notifySafely();
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null || !_current(token)) return;
      final before = more && held.posts.isNotEmpty
          ? held.posts.last.createdAt
          : null;
      final page = mentions
          ? await auth.run(
              () => api.mentions(
                siteUrl: instance.url,
                groupName: groupName,
                apiKey: auth.apiKey,
                clientId: auth.apiKey == null ? null : auth.clientId,
                before: before,
              ),
            )
          : await auth.run(
              () => api.posts(
                siteUrl: instance.url,
                groupName: groupName,
                apiKey: auth.apiKey,
                clientId: auth.apiKey == null ? null : auth.clientId,
                before: before,
              ),
            );
      _commit(token, () {
        final current = _activities[key];
        if (current == null) return;
        final rows = more ? [...current.posts] : <GroupActivityPost>[];
        final seen = {for (final post in rows) post.id};
        for (final post in page.posts) {
          if (seen.add(post.id)) rows.add(post);
        }
        _activities[key] = GroupActivityState(
          posts: List.unmodifiable(rows),
          hasMore:
              page.hasMore && (before == null || page.before!.isBefore(before)),
          loaded: true,
        );
      });
    } catch (error) {
      _fail(token, () {
        final current = _activities[key];
        if (current == null) return;
        _activities[key] = GroupActivityState._(
          posts: current.posts,
          hasMore: current.hasMore,
          loaded: true,
          error: more
              ? appL10n.couldnTLoadMoreActivity
              : appL10n.couldnTLoadGroupActivity,
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<void> loadPermissions(
    DiscourseInstance instance,
    String groupName, {
    bool refresh = false,
  }) async {
    if (isDisposed) return;
    final key = _groupKey(instance.url, groupName);
    final requestKey = ('permissions', key);
    _touchQuery(_permissions, key);
    final held = permissionsState(instance.url, groupName);
    if (_requests.containsKey(requestKey) || (!refresh && held.loaded)) return;
    final token = _start(requestKey, instance.url, groupName: groupName);
    _permissions[key] = GroupPermissionsState._(
      permissions: held.permissions,
      loading: true,
      loaded: held.loaded,
    );
    _trimQueries(
      _permissions,
      instance.url,
      siteOf: (key) => key.siteUrl,
      requestKeyOf: (key) => ('permissions', key),
    );
    notifySafely();
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null || !_current(token)) return;
      final rows = await auth.run(
        () => api.permissions(
          siteUrl: instance.url,
          apiKey: auth.apiKey,
          clientId: auth.apiKey == null ? null : auth.clientId,
          groupName: groupName,
        ),
      );
      _commit(token, () {
        _permissions[key] = GroupPermissionsState(
          permissions: rows,
          loaded: true,
        );
      });
    } catch (error) {
      _fail(token, () {
        _permissions[key] = GroupPermissionsState._(
          permissions: held.permissions,
          loaded: true,
          error: appL10n.couldnTLoadGroupPermissions,
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<void> loadLogs(
    DiscourseInstance instance,
    String groupName, {
    bool refresh = false,
    bool more = false,
  }) async {
    if (isDisposed) return;
    final key = _groupKey(instance.url, groupName);
    final requestKey = ('logs', key);
    _touchQuery(_logs, key);
    final held = logsState(instance.url, groupName);
    if (_requests.containsKey(requestKey) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }
    final token = _start(requestKey, instance.url, groupName: groupName);
    _logs[key] = GroupLogsState._(
      logs: held.logs,
      nextPage: held.nextPage,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    _trimQueries(
      _logs,
      instance.url,
      siteOf: (key) => key.siteUrl,
      requestKeyOf: (key) => ('logs', key),
    );
    notifySafely();
    try {
      final auth = await _requiredCredentials(instance, token);
      if (auth == null || !_current(token)) return;
      final page = await auth.run(
        () => api.logs(
          siteUrl: instance.url,
          apiKey: auth.apiKey!,
          clientId: auth.apiKey == null ? null : auth.clientId,
          groupName: groupName,
          offset: more ? held.nextPage : 0,
        ),
      );
      _commit(token, () {
        final current = _logs[key];
        if (current == null) return;
        _logs[key] = GroupLogsState(
          logs: List.unmodifiable([if (more) ...current.logs, ...page.logs]),
          nextPage: (more ? held.nextPage : 0) + 1,
          hasMore: page.logs.isNotEmpty && !page.allLoaded,
          loaded: true,
        );
      });
    } catch (error) {
      _fail(token, () {
        final current = _logs[key];
        if (current == null) return;
        _logs[key] = GroupLogsState._(
          logs: current.logs,
          nextPage: current.nextPage,
          hasMore: current.hasMore,
          loaded: true,
          error: more
              ? appL10n.couldnTLoadMoreGroupLogs
              : appL10n.couldnTLoadGroupLogs,
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<GroupWriteOutcome<void>> join(
    DiscourseInstance instance,
    Group group,
  ) async {
    final joined = await _mutate(
      instance,
      group,
      (apiKey, clientId) => api.join(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
      ),
    );
    if (joined.canApplyLocally) await _refreshMemberLists(instance, group);
    return joined;
  }

  Future<GroupWriteOutcome<void>> leave(
    DiscourseInstance instance,
    Group group,
  ) {
    final reader = instance.user?.username.toLowerCase();
    return _mutate(
      instance,
      group,

      (apiKey, clientId) => api.leave(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
      ),
      removeCachedRows: reader == null
          ? null
          : () => _removeCachedMembers(
              instance.url,
              group,
              (member) => member.username.toLowerCase() == reader,
            ),
    );
  }

  Future<GroupWriteOutcome<String?>> requestMembership(
    DiscourseInstance instance,
    Group group,
    String reason,
  ) => _mutate(
    instance,
    group,
    (apiKey, clientId) => api.requestMembership(
      siteUrl: instance.url,
      apiKey: apiKey,
      clientId: clientId,
      groupName: group.name,
      reason: reason,
    ),
    refreshDetail: false,
  );

  Future<GroupWriteOutcome<void>> handleRequest(
    DiscourseInstance instance,
    Group group,
    GroupRequester requester, {
    required bool accept,
  }) async {
    final handled = await _mutate(
      instance,
      group,
      (apiKey, clientId) => api.handleMembershipRequest(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
        userId: requester.id,
        accept: accept,
      ),
      refreshDetail: false,
      removeCachedRows: () {
        final keys = _requesters.keys.where(
          (key) =>
              key.siteUrl == instance.url &&
              key.groupName == _normalize(group.name),
        );
        for (final key in keys.toList()) {
          final held = _requesters[key]!;
          final rows = held.requesters
              .where((item) => item.id != requester.id)
              .toList(growable: false);
          final removed = held.requesters.length - rows.length;
          if (removed == 0) continue;
          _requesters[key] = GroupRequestersState(
            requesters: rows,
            total: _subtractRemovedRows(held.total, removed),
            nextOffset: _subtractRemovedRows(held.nextOffset, removed),
            hasMore: held.hasMore,
            loading: held.loading,
            loadingMore: held.loadingMore,
            loaded: held.loaded,
            error: held.error,
            pageError: held.pageError,
          );
        }
      },
    );
    if (accept && handled.canApplyLocally) {
      await _refreshMemberLists(instance, group);
    }
    return handled;
  }

  Future<GroupWriteOutcome<GroupMembershipMutationResult>> addMembers(
    DiscourseInstance instance,
    Group group,
    GroupAddMembersCommand command, {
    String filter = '',
    String? order,
    bool ascending = true,
  }) async {
    final result = await _mutate(
      instance,
      group,
      (apiKey, clientId) => api.addMembers(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
        usernames: command.usernames,
        emails: command.emails,
      ),
    );
    if (!result.canApplyLocally) return result;
    final membersRefreshed = await _refreshMemberLists(
      instance,
      group,
      shown: _memberListKey(instance.url, group.name, filter, order, ascending),
    );
    final accepted =
        result as GroupWriteAccepted<GroupMembershipMutationResult>;
    return accepted.withProjection(
      (isDisposed || !accepted.isCurrent)
          ? GroupProjectionFreshness.retired
          : membersRefreshed &&
                accepted.projection == GroupProjectionFreshness.refreshed
          ? GroupProjectionFreshness.refreshed
          : GroupProjectionFreshness.stale,
      current: !isDisposed && accepted.isCurrent,
    );
  }

  Future<GroupWriteOutcome<GroupInvite>> createInvite(
    DiscourseInstance instance,
    Group group, {
    String? email,
    String? customMessage,
    int maxRedemptionsAllowed = 1,
    DateTime? expiresAt,
  }) => _mutate(
    instance,
    group,
    (apiKey, clientId) => api.createInvite(
      siteUrl: instance.url,
      apiKey: apiKey,
      clientId: clientId,
      groupId: group.id,
      email: email,
      customMessage: customMessage,
      maxRedemptionsAllowed: maxRedemptionsAllowed,
      expiresAt: expiresAt,
    ),
    refreshDetail: false,
  );

  Future<GroupWriteOutcome<void>> removeMember(
    DiscourseInstance instance,
    Group group,
    GroupMember member,
  ) => _mutate(
    instance,
    group,

    (apiKey, clientId) => api.removeMembers(
      siteUrl: instance.url,
      apiKey: apiKey,
      clientId: clientId,
      groupId: group.id,
      userIds: [member.id],
    ),
    removeCachedRows: () => _removeCachedMembers(
      instance.url,
      group,
      (item) => item.id == member.id,
    ),
  );

  /// Refreshes [shown] and every other cached member list of [group] after a
  /// write that adds members. A page shows a list it loaded earlier from the
  /// cache when it returns to it, so a list left alone would lack the members.
  Future<bool> _refreshMemberLists(
    DiscourseInstance instance,
    Group group, {
    _MemberListKey? shown,
  }) async {
    final groupName = _normalize(group.name);
    final keys = {
      ?shown,
      ..._members.keys.where(
        (key) => key.siteUrl == instance.url && key.groupName == groupName,
      ),
    };
    final refreshed = await Future.wait([
      for (final key in keys)
        loadMembers(
          instance,
          group.name,
          filter: key.filter,
          order: key.order,
          ascending: key.ascending,
          refresh: true,
        ),
    ]);
    return refreshed.every((ok) => ok);
  }

  void _removeCachedMembers(
    String siteUrl,
    Group group,
    bool Function(GroupMember member) removes,
  ) {
    _members.updateAll((key, held) {
      if (key.siteUrl != siteUrl || key.groupName != _normalize(group.name)) {
        return held;
      }
      final rows = held.members
          .where((item) => !removes(item))
          .toList(growable: false);
      final removed = held.members.length - rows.length;
      if (removed == 0) return held;
      return GroupMembersState(
        members: rows,
        total: _subtractRemovedRows(held.total, removed),
        nextOffset: _subtractRemovedRows(held.nextOffset, removed),
        hasMore: held.hasMore,
        loading: held.loading,
        loadingMore: held.loadingMore,
        loaded: held.loaded,
        error: held.error,
        pageError: held.pageError,
      );
    });
  }

  Future<GroupWriteOutcome<void>> setMemberOwner(
    DiscourseInstance instance,
    Group group,
    GroupMember member, {
    required bool owner,
  }) async {
    final saved = await _mutate(
      instance,
      group,

      (apiKey, clientId) => owner
          ? api.addOwners(
              siteUrl: instance.url,
              apiKey: apiKey,
              clientId: clientId,
              groupId: group.id,
              usernames: [member.username],
            )
          : api.removeOwners(
              siteUrl: instance.url,
              apiKey: apiKey,
              clientId: clientId,
              groupId: group.id,
              usernames: [member.username],
            ),
      refreshDetail: false,
    );
    if (saved.canApplyLocally) {
      _updateMember(instance, group, member, owner: owner);
    }
    return saved;
  }

  Future<GroupWriteOutcome<void>> setMemberPrimary(
    DiscourseInstance instance,
    Group group,
    GroupMember member, {
    required bool primary,
  }) async {
    final saved = await _mutate(
      instance,
      group,

      (apiKey, clientId) => api.setPrimaryGroup(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
        usernames: [member.username],
        primary: primary,
      ),
      refreshDetail: false,
    );
    if (saved.canApplyLocally) {
      _updateMember(instance, group, member, primary: primary);
    }
    return saved;
  }

  Future<GroupWriteOutcome<void>> deleteGroup(
    DiscourseInstance instance,
    Group group,
  ) async {
    final saved = await _mutate(
      instance,
      group,

      (apiKey, clientId) => api.deleteGroup(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
      ),
      refreshDetail: false,
    );
    if (!saved.canApplyLocally) return saved;
    final normalized = _normalize(group.name);
    _requests.removeWhere(
      (_, request) =>
          request.siteUrl == instance.url &&
          (request.groupName == null || request.groupName == normalized),
    );
    _details.remove(_groupKey(instance.url, group.name));
    _members.removeWhere(
      (key, _) => key.siteUrl == instance.url && key.groupName == normalized,
    );
    _requesters.removeWhere(
      (key, _) => key.siteUrl == instance.url && key.groupName == normalized,
    );
    _activities.removeWhere(
      (key, _) => key.siteUrl == instance.url && key.groupName == normalized,
    );
    _permissions.remove(_groupKey(instance.url, group.name));
    _logs.remove(_groupKey(instance.url, group.name));
    // The group may appear in any directory filter or on an unloaded page.
    // Dropping the site's directory snapshots makes the destination opened
    // after deletion fetch authoritative totals and rows.
    _directories.removeWhere((key, _) => key.siteUrl == instance.url);
    notifySafely();
    return saved;
  }

  void _updateMember(
    DiscourseInstance instance,
    Group group,
    GroupMember member, {
    bool? owner,
    bool? primary,
  }) {
    _members.updateAll((key, held) {
      if (key.siteUrl != instance.url ||
          key.groupName != _normalize(group.name)) {
        return held;
      }
      return GroupMembersState(
        members: List.unmodifiable([
          for (final item in held.members)
            if (item.id == member.id)
              item.copyWith(owner: owner, primary: primary)
            else
              item,
        ]),
        total: held.total,
        nextOffset: held.nextOffset,
        hasMore: held.hasMore,
        loaded: held.loaded,
      );
    });
    notifySafely();
  }

  Future<GroupWriteOutcome<Group>> updateGroup(
    DiscourseInstance instance,
    Group group,
    GroupUpdateCommand command,
  ) async {
    final attempt = _GroupUpdateAttempt(
      instance,
      group,
      command,
      lifecycle.capture(instance.url),
    );
    final result = await _writeUpdate(attempt);
    final key = _groupKey(instance.url, group.name);
    if (identical(_pendingUpdates[key], attempt)) {
      if (result case GroupWriteFailed<Group>(
        error: WriteException(statusCode: 422, :final affectedUserCount?),
      ) when affectedUserCount > 0 && !isDisposed && attempt.lease.isCurrent) {
        final confirmation = GroupUpdateConfirmation(
          affectedUserCount,
          groupName: group.name,
        );
        _confirmationAttempts[confirmation] = attempt;
        return confirmation;
      }
      _pendingUpdates.remove(key);
    }
    return result;
  }

  Future<GroupWriteOutcome<Group>> confirmUpdate(
    GroupUpdateConfirmation confirmation, {
    required bool applyToExistingUsers,
  }) {
    final attempt = _confirmationAttempts[confirmation];
    if (attempt == null) {
      return Future.value(
        const GroupWriteNotAdmitted(GroupWriteAdmission.expiredConfirmation),
      );
    }
    final key = _groupKey(attempt.instance.url, attempt.group.name);
    if (isDisposed ||
        !attempt.lease.isCurrent ||
        !identical(_pendingUpdates[key], attempt)) {
      return Future.value(
        const GroupWriteNotAdmitted(GroupWriteAdmission.expiredConfirmation),
      );
    }
    _pendingUpdates.remove(key);
    return _writeUpdate(attempt, updateExistingUsers: applyToExistingUsers);
  }

  void cancelUpdate(GroupUpdateConfirmation confirmation) {
    final attempt = _confirmationAttempts[confirmation];
    if (attempt == null) return;
    final key = _groupKey(attempt.instance.url, attempt.group.name);
    if (identical(_pendingUpdates[key], attempt)) {
      _pendingUpdates.remove(key);
    }
  }

  Future<GroupWriteOutcome<Group>> _writeUpdate(
    _GroupUpdateAttempt attempt, {
    bool? updateExistingUsers,
  }) {
    late GroupUpdateAcknowledgment acknowledgment;
    return _mutate(
      attempt.instance,
      attempt.group,
      (apiKey, clientId) async {
        acknowledgment = await api.updateGroup(
          siteUrl: attempt.instance.url,
          apiKey: apiKey,
          clientId: clientId,
          groupId: attempt.group.id,
          values: attempt.command.values,
          updateExistingUsers: updateExistingUsers,
        );
        return acknowledgment.returnedGroup ?? attempt.group;
      },
      reconcileAccepted: (value, auth, current) => _reconcileUpdate(
        attempt.instance,
        attempt.group,
        acknowledgment,
        auth,
        current,
      ),
      lease: attempt.lease,
      updateAttempt: updateExistingUsers == null ? attempt : null,
    );
  }

  Future<({Group value, GroupProjectionFreshness freshness})> _reconcileUpdate(
    DiscourseInstance instance,
    Group original,
    GroupUpdateAcknowledgment acknowledgment,
    AccountRequestCredentials auth,
    bool Function() current,
  ) async {
    final returned = acknowledgment.returnedGroup;
    if (returned != null) {
      _unreconciledUpdates.remove(_groupKey(instance.url, original.name));
      _projectUpdatedGroup(instance.url, original, returned);
      final refreshed = await loadDetail(
        instance,
        returned.name,
        refresh: true,
      );
      return (
        value: returned,
        freshness: refreshed
            ? GroupProjectionFreshness.refreshed
            : GroupProjectionFreshness.stale,
      );
    }
    final key = _groupKey(instance.url, original.name);
    try {
      if (!current()) {
        return (value: original, freshness: GroupProjectionFreshness.retired);
      }
      final detail = await auth.run(
        () => api.detailById(
          siteUrl: instance.url,
          groupId: acknowledgment.groupId,
          apiKey: auth.apiKey,
          clientId: auth.clientId,
        ),
      );
      if (!current()) {
        return (value: original, freshness: GroupProjectionFreshness.retired);
      }
      _unreconciledUpdates.remove(key);
      _projectUpdatedGroup(instance.url, original, detail.group);
      _details[_groupKey(instance.url, detail.group.name)] = GroupDetailState(
        detail: detail,
        loaded: true,
      );
      return (
        value: detail.group,
        freshness: GroupProjectionFreshness.refreshed,
      );
    } catch (error) {
      if (current()) {
        final held = _details[key]?.detail;
        _invalidateUnknownUpdate(instance.url, original);
        _unreconciledUpdates[key] = original;
        _trimQueries(
          _unreconciledUpdates,
          instance.url,
          siteOf: (key) => key.siteUrl,
        );
        _details[key] = GroupDetailState(
          detail: error is SiteLookupException && error.statusCode == 404
              ? null
              : held ?? GroupDetail(group: original),
          loaded: true,
          error: appL10n.couldnTLoadThisGroup,
        );
      }
      return (value: original, freshness: GroupProjectionFreshness.stale);
    }
  }

  void _invalidateUnknownUpdate(String siteUrl, Group original) {
    final name = _normalize(original.name);
    _requests.removeWhere(
      (_, request) =>
          request.siteUrl == siteUrl &&
          (request.groupName == name || request.key is _DirectoryKey),
    );
    _members.removeWhere(
      (key, _) => key.siteUrl == siteUrl && key.groupName == name,
    );
    _requesters.removeWhere(
      (key, _) => key.siteUrl == siteUrl && key.groupName == name,
    );
    _activities.removeWhere(
      (key, _) => key.siteUrl == siteUrl && key.groupName == name,
    );
    _permissions.remove(_groupKey(siteUrl, name));
    _logs.remove(_groupKey(siteUrl, name));
    _directories.removeWhere((key, _) => key.siteUrl == siteUrl);
  }

  void _projectUpdatedGroup(String siteUrl, Group original, Group updated) {
    final oldKey = _groupKey(siteUrl, original.name);
    final newKey = _groupKey(siteUrl, updated.name);
    _requests.remove(newKey);
    final held = _details[oldKey];
    if (oldKey != newKey) {
      final names = {oldKey.groupName, newKey.groupName};
      _requests.removeWhere(
        (_, request) =>
            request.siteUrl == siteUrl && names.contains(request.groupName),
      );
      _details.remove(oldKey);
      _members.removeWhere(
        (key, _) => key.siteUrl == siteUrl && names.contains(key.groupName),
      );
      _requesters.removeWhere(
        (key, _) => key.siteUrl == siteUrl && names.contains(key.groupName),
      );
      _activities.removeWhere(
        (key, _) => key.siteUrl == siteUrl && names.contains(key.groupName),
      );
      _permissions.removeWhere(
        (key, _) => key.siteUrl == siteUrl && names.contains(key.groupName),
      );
      _logs.removeWhere(
        (key, _) => key.siteUrl == siteUrl && names.contains(key.groupName),
      );
    }
    _projectDirectoryGroup(siteUrl, updated);
    _details[newKey] = GroupDetailState(
      detail: GroupDetail(
        group: updated,
        visibleGroupNames: held?.detail?.visibleGroupNames ?? const [],
      ),
      loaded: true,
    );
  }

  /// Replaces [updated]'s row in every cached directory list of [siteUrl],
  /// and in directory pages still loading, with this newer server copy. The
  /// directory is shown from its cache when the page returns to it.
  void _projectDirectoryGroup(String siteUrl, Group updated) {
    for (final request in _requests.values) {
      if (request.siteUrl == siteUrl && request.key is _DirectoryKey) {
        request.directoryReplacements[updated.id] = updated;
      }
    }
    for (final entry in _directories.entries) {
      final state = entry.value;
      if (entry.key.siteUrl != siteUrl ||
          !state.groups.any((group) => group.id == updated.id)) {
        continue;
      }
      _directories[entry.key] = GroupDirectoryState._(
        groups: List.unmodifiable([
          for (final group in state.groups)
            group.id == updated.id ? updated : group,
        ]),
        typeFilters: state.typeFilters,
        totalRows: state.totalRows,
        nextPage: state.nextPage,
        hasMore: state.hasMore,
        loading: state.loading,
        loadingMore: state.loadingMore,
        loaded: state.loaded,
        error: state.error,
        pageError: state.pageError,
      );
    }
  }

  Future<GroupWriteOutcome<T>> _mutate<T>(
    DiscourseInstance instance,
    Group group,
    Future<T> Function(String apiKey, String clientId) write, {
    bool refreshDetail = true,
    Future<({T value, GroupProjectionFreshness freshness})> Function(
      T value,
      AccountRequestCredentials auth,
      bool Function() current,
    )?
    reconcileAccepted,
    VoidCallback? removeCachedRows,
    SiteLease? lease,
    _GroupUpdateAttempt? updateAttempt,
  }) async {
    final key = _groupKey(instance.url, group.name);
    final account = lease ?? lifecycle.capture(instance.url);
    if (isDisposed || !account.isCurrent) {
      return const GroupWriteNotAdmitted(GroupWriteAdmission.inactive);
    }
    if (_mutations.containsKey(key)) {
      return const GroupWriteNotAdmitted(GroupWriteAdmission.busy);
    }
    _pendingUpdates.remove(key);
    if (updateAttempt != null) _pendingUpdates[key] = updateAttempt;
    final token = _GroupMutation(removesRows: removeCachedRows != null);
    _mutations[key] = token;
    final held = detailState(instance.url, group.name);
    _details[key] = GroupDetailState(
      detail: held.detail,
      loaded: held.loaded,
      mutating: true,
    );
    notifySafely();
    var dispatched = false;
    var ownsCompletion = false;
    late T value;
    var projection = GroupProjectionFreshness.notRequested;
    bool current() =>
        !isDisposed && account.isCurrent && identical(_mutations[key], token);
    try {
      final auth = await AccountRequestSession(
        instance.url,
        account,
      ).credentials(credentials);
      if (!current()) {
        return const GroupWriteNotAdmitted(GroupWriteAdmission.inactive);
      }
      final apiKey = auth.apiKey;
      if (apiKey == null) {
        return const GroupWriteNotAdmitted(GroupWriteAdmission.noCredentials);
      }
      value = await auth.run(() {
        dispatched = true;
        return write(apiKey, auth.clientId);
      });
      if (current()) {
        removeCachedRows?.call();
        token.finishRemoval();
        if (reconcileAccepted != null) {
          final reconciled = await reconcileAccepted(value, auth, current);
          value = reconciled.value;
          projection = reconciled.freshness;
        } else {
          _details[key] = GroupDetailState(
            detail: held.detail,
            loaded: held.loaded,
          );
          if (refreshDetail) {
            _requests.remove(key);
            final refreshed = await loadDetail(
              instance,
              group.name,
              refresh: true,
            );
            projection = refreshed
                ? GroupProjectionFreshness.refreshed
                : GroupProjectionFreshness.stale;
          }
        }
      }
    } catch (error) {
      if (current()) {
        _details[key] = GroupDetailState(
          detail: held.detail,
          loaded: held.loaded,
          error: _saveFailureMessage,
        );
      }
      return GroupWriteFailed(error, dispatched: dispatched);
    } finally {
      token.finishRemoval();
      ownsCompletion = identical(_mutations[key], token);
      if (!isDisposed && identical(_mutations[key], token)) {
        _mutations.remove(key);
        final state = detailState(instance.url, group.name);
        if (state.mutating) {
          _details[key] = GroupDetailState(
            detail: state.detail,
            loaded: state.loaded,
            error: state.error,
          );
        }
        notifySafely();
      }
    }
    final active = ownsCompletion && !isDisposed && account.isCurrent;
    return GroupWriteAccepted(
      value,
      projection: active ? projection : GroupProjectionFreshness.retired,
      current: active,
      account: account,
    );
  }

  void _touchQuery<K, V>(Map<K, V> states, K key) {
    final held = states.remove(key);
    if (held != null) states[key] = held;
  }

  void _trimQueries<K, V>(
    Map<K, V> states,
    String siteUrl, {
    required String Function(K) siteOf,
    Object Function(K)? requestKeyOf,
    bool Function(K)? pinned,
  }) {
    final keys = states.keys
        .where((key) => siteOf(key) == siteUrl)
        .toList(growable: false);
    if (keys.length <= _cachedQueriesPerSite) return;
    for (final key in keys.take(keys.length - _cachedQueriesPerSite)) {
      if (pinned?.call(key) ?? false) continue;
      states.remove(key);
      // Eviction also revokes the old page, so returning to this query can
      // load immediately without an earlier completion replacing it.
      _requests.remove(requestKeyOf == null ? key : requestKeyOf(key));
    }
  }

  void forget(String siteUrl) {
    _directories.removeWhere((key, _) => key.siteUrl == siteUrl);
    _details.removeWhere((key, _) => key.siteUrl == siteUrl);
    _pendingUpdates.removeWhere((key, _) => key.siteUrl == siteUrl);
    _unreconciledUpdates.removeWhere((key, _) => key.siteUrl == siteUrl);
    _members.removeWhere((key, _) => key.siteUrl == siteUrl);
    _requesters.removeWhere((key, _) => key.siteUrl == siteUrl);
    _activities.removeWhere((key, _) => key.siteUrl == siteUrl);
    _permissions.removeWhere((key, _) => key.siteUrl == siteUrl);
    _logs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _presentedDirectoryQueries.remove(siteUrl);
    _mutations.removeWhere((key, mutation) {
      if (key.siteUrl != siteUrl) return false;
      mutation.finishRemoval();
      return true;
    });
    _requests.removeWhere((_, request) => request.siteUrl == siteUrl);
    notifySafely();
  }

  _GroupRequest _start(Object key, String siteUrl, {String? groupName}) {
    final request = _GroupRequest(
      key: key,
      siteUrl: siteUrl,
      lease: lifecycle.capture(siteUrl),
      groupName: groupName == null ? null : _normalize(groupName),
    );
    _requests[key] = request;
    return request;
  }

  bool _current(_GroupRequest request) =>
      !isDisposed &&
      request.lease.isCurrent &&
      identical(_requests[request.key], request);

  Future<AccountRequestCredentials?> _credentialsFor(
    DiscourseInstance instance,
    _GroupRequest request,
  ) async {
    if (!_current(request)) return null;
    final session = AccountRequestSession(instance.url, request.lease);
    final auth = instance.isConnected
        ? await session.credentials(credentials)
        : session.anonymousCredentials();
    return _current(request) ? auth : null;
  }

  Future<AccountRequestCredentials?> _requiredCredentials(
    DiscourseInstance instance,
    _GroupRequest request,
  ) async {
    final auth = await _credentialsFor(instance, request);
    if (auth == null || auth.apiKey != null) return auth;
    throw StateError('This group page requires a connected account.');
  }

  /// Ids a mutation took out of [heldRows] while a page for the same list
  /// was in flight. Its rows, offset and total may predate the mutation.
  static Set<int> _removedDuringLoad<T>(
    List<T> heldRows,
    List<T> currentRows,
    int Function(T row) idOf,
  ) {
    if (identical(heldRows, currentRows)) return const {};
    final currentIds = {for (final row in currentRows) idOf(row)};
    return {
      for (final row in heldRows)
        if (!currentIds.contains(idOf(row))) idOf(row),
    };
  }

  static int _subtractRemovedRows(int value, int removed) =>
      value > removed ? value - removed : 0;

  void _commit(_GroupRequest request, VoidCallback mutation) {
    if (!_current(request)) return;
    request.lease.commit(() {
      if (!_current(request)) return;
      mutation();
      notifySafely();
    });
  }

  void _fail(_GroupRequest request, VoidCallback mutation) {
    if (!_current(request)) return;

    _commit(request, mutation);
  }

  void _finish(_GroupRequest request) {
    if (identical(_requests[request.key], request)) {
      _requests.remove(request.key);
    }
  }

  static _GroupKey _groupKey(String siteUrl, String groupName) =>
      (siteUrl: siteUrl, groupName: _normalize(groupName));

  static _MemberListKey _memberListKey(
    String siteUrl,
    String groupName,
    String filter,
    String? order,
    bool ascending,
  ) => (
    siteUrl: siteUrl,
    groupName: _normalize(groupName),
    filter: filter.trim(),
    order: order?.trim().isEmpty == true ? null : order?.trim(),
    ascending: ascending,
  );

  static _FilterListKey _filterListKey(
    String siteUrl,
    String groupName,
    String filter,
  ) => (
    siteUrl: siteUrl,
    groupName: _normalize(groupName),
    filter: filter.trim(),
  );

  static String _normalize(String value) => value.trim().toLowerCase();

  @override
  void dispose() {
    _pendingUpdates.clear();
    _unreconciledUpdates.clear();
    _requests.clear();
    for (final mutation in _mutations.values) {
      mutation.finishRemoval();
    }
    _mutations.clear();
    super.dispose();
  }
}
