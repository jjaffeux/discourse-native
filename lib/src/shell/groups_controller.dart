import 'package:flutter/foundation.dart';

import '../data/api_credentials.dart';
import '../data/groups_api.dart';
import '../data/site_lifecycle.dart';
import '../diagnostics/diagnostics_controller.dart';
import '../foundation/frame_safe_notifier.dart';
import '../models/discourse_instance.dart';
import '../models/group.dart';

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

@immutable
final class GroupDirectoryState {
  const GroupDirectoryState({
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
  const GroupMembersState({
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
  const GroupRequestersState({
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
  const GroupActivityState({
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
  const GroupPermissionsState({
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
  const GroupLogsState({
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
typedef _GroupCredentials = ({String? apiKey, String? clientId});

/// Independent, account-generation-safe state for the native group pages.
final class GroupsController extends FrameSafeNotifier {
  GroupsController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
  });

  final GroupsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;

  final Map<_DirectoryKey, GroupDirectoryState> _directories = {};
  final Map<_GroupKey, GroupDetailState> _details = {};
  final Map<_MemberListKey, GroupMembersState> _members = {};
  final Map<_FilterListKey, GroupRequestersState> _requesters = {};
  final Map<_ActivityKey, GroupActivityState> _activities = {};
  final Map<_GroupKey, GroupPermissionsState> _permissions = {};
  final Map<_GroupKey, GroupLogsState> _logs = {};
  final Map<String, GroupDirectoryQuery> _presentedDirectoryQueries = {};
  final Map<Object, Object> _requests = {};
  final Map<_GroupKey, Object> _mutations = {};

  GroupDirectoryState directoryState(
    String siteUrl,
    GroupDirectoryQuery query,
  ) =>
      _directories[(siteUrl: siteUrl, query: query)] ??
      const GroupDirectoryState();

  /// The directory state currently represented by the controls for a site.
  ///
  /// The shell header lives outside the directory host, so this small
  /// pointer lets it present the matching result count without duplicating the
  /// host's query ownership or persisting filter state in navigation history.
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
      const GroupMembersState();

  GroupRequestersState requestersState(
    String siteUrl,
    String groupName, {
    String filter = '',
  }) =>
      _requesters[_filterListKey(siteUrl, groupName, filter)] ??
      const GroupRequestersState();

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
      const GroupActivityState();

  GroupPermissionsState permissionsState(String siteUrl, String groupName) =>
      _permissions[_groupKey(siteUrl, groupName)] ??
      const GroupPermissionsState();

  GroupLogsState logsState(String siteUrl, String groupName) =>
      _logs[_groupKey(siteUrl, groupName)] ?? const GroupLogsState();

  Future<void> loadDirectory(
    DiscourseInstance instance,
    GroupDirectoryQuery query, {
    bool refresh = false,
    bool more = false,
  }) async {
    final key = (siteUrl: instance.url, query: query);
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
    _directories[key] = GroupDirectoryState(
      groups: held.groups,
      typeFilters: held.typeFilters,
      totalRows: held.totalRows,
      nextPage: held.nextPage,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    notifySafely();
    if (!_current(token)) return;
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null) return;
      final page = await api.directory(
        siteUrl: instance.url,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
        page: more ? held.nextPage : 0,
        filter: query.filter,
        type: query.type,
        username: query.username,
      );
      _commit(token, () {
        final rows = more ? [...held.groups] : <Group>[];
        final seen = {for (final group in rows) group.id};
        for (final group in page.groups) {
          if (seen.add(group.id)) rows.add(group);
        }
        _directories[key] = GroupDirectoryState(
          groups: List.unmodifiable(rows),
          typeFilters: page.typeFilters,
          totalRows: page.totalRows,
          nextPage: (more ? held.nextPage : 0) + 1,
          hasMore: page.nextPagePath != null,
          loaded: true,
        );
      });
    } catch (error, stackTrace) {
      _fail(token, 'groups.directory', error, stackTrace, () {
        _directories[key] = GroupDirectoryState(
          groups: held.groups,
          typeFilters: held.typeFilters,
          totalRows: held.totalRows,
          nextPage: held.nextPage,
          hasMore: held.hasMore,
          loaded: true,
          error: more
              ? "Couldn't load more groups."
              : "Couldn't load the group directory.",
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<void> loadDetail(
    DiscourseInstance instance,
    String groupName, {
    bool refresh = false,
  }) async {
    final key = _groupKey(instance.url, groupName);
    final held = detailState(instance.url, groupName);
    if (_requests.containsKey(key) || (!refresh && held.loaded)) return;
    final token = _start(key, instance.url);
    _details[key] = GroupDetailState(
      detail: held.detail,
      loading: true,
      loaded: held.loaded,
      mutating: held.mutating,
    );
    notifySafely();
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null) return;
      final detail = await api.detail(
        siteUrl: instance.url,
        groupName: groupName,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
      );
      _commit(token, () {
        _details[key] = GroupDetailState(detail: detail, loaded: true);
      });
    } catch (error, stackTrace) {
      _fail(token, 'groups.detail', error, stackTrace, () {
        _details[key] = GroupDetailState(
          detail: held.detail,
          loaded: true,
          error: "Couldn't load this group.",
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<void> loadMembers(
    DiscourseInstance instance,
    String groupName, {
    String filter = '',
    String? order,
    bool ascending = true,
    bool refresh = false,
    bool more = false,
  }) async {
    final key = _memberListKey(
      instance.url,
      groupName,
      filter,
      order,
      ascending,
    );
    final held = membersState(
      instance.url,
      groupName,
      filter: filter,
      order: order,
      ascending: ascending,
    );
    if (_requests.containsKey(key) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }
    final token = _start(key, instance.url);
    _members[key] = GroupMembersState(
      members: held.members,
      total: held.total,
      nextOffset: held.nextOffset,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    notifySafely();
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null) return;
      final page = await api.members(
        siteUrl: instance.url,
        groupName: groupName,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
        offset: more ? held.nextOffset : 0,
        order: order,
        ascending: ascending,
        filter: filter,
      );
      _commit(token, () {
        final rows = more ? [...held.members] : <GroupMember>[];
        final seen = {for (final member in rows) member.id};
        for (final member in page.members) {
          if (seen.add(member.id)) rows.add(member);
        }
        _members[key] = GroupMembersState(
          members: List.unmodifiable(rows),
          total: page.total,
          nextOffset: page.nextOffset,
          hasMore: page.hasMore,
          loaded: true,
        );
      });
    } catch (error, stackTrace) {
      _fail(token, 'groups.members', error, stackTrace, () {
        _members[key] = GroupMembersState(
          members: held.members,
          total: held.total,
          nextOffset: held.nextOffset,
          hasMore: held.hasMore,
          loaded: true,
          error: more
              ? "Couldn't load more members."
              : "Couldn't load group members.",
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<void> loadRequesters(
    DiscourseInstance instance,
    String groupName, {
    String filter = '',
    bool refresh = false,
    bool more = false,
  }) async {
    final key = _filterListKey(instance.url, groupName, filter);
    final held = requestersState(instance.url, groupName, filter: filter);
    if (_requests.containsKey(('requesters', key)) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }
    final requestKey = ('requesters', key);
    final token = _start(requestKey, instance.url);
    _requesters[key] = GroupRequestersState(
      requesters: held.requesters,
      total: held.total,
      nextOffset: held.nextOffset,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    notifySafely();
    try {
      final auth = await _requiredCredentials(instance, token);
      if (auth == null) return;
      final page = await api.requesters(
        siteUrl: instance.url,
        apiKey: auth.apiKey!,
        clientId: auth.clientId,
        groupName: groupName,
        offset: more ? held.nextOffset : 0,
        filter: filter,
      );
      _commit(token, () {
        final rows = more ? [...held.requesters] : <GroupRequester>[];
        final seen = {for (final requester in rows) requester.id};
        for (final requester in page.requesters) {
          if (seen.add(requester.id)) rows.add(requester);
        }
        _requesters[key] = GroupRequestersState(
          requesters: List.unmodifiable(rows),
          total: page.total,
          nextOffset: page.nextOffset,
          hasMore: page.hasMore,
          loaded: true,
        );
      });
    } catch (error, stackTrace) {
      _fail(token, 'groups.requests', error, stackTrace, () {
        _requesters[key] = GroupRequestersState(
          requesters: held.requesters,
          total: held.total,
          nextOffset: held.nextOffset,
          hasMore: held.hasMore,
          loaded: true,
          error: more
              ? "Couldn't load more requests."
              : "Couldn't load membership requests.",
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
    final key = (
      siteUrl: instance.url,
      groupName: _normalize(groupName),
      mentions: mentions,
    );
    final held = activityState(instance.url, groupName, mentions: mentions);
    if (_requests.containsKey(key) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }
    final token = _start(key, instance.url);
    _activities[key] = GroupActivityState(
      posts: held.posts,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    notifySafely();
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null) return;
      final before = more && held.posts.isNotEmpty
          ? held.posts.last.createdAt
          : null;
      final page = mentions
          ? await api.mentions(
              siteUrl: instance.url,
              groupName: groupName,
              apiKey: auth.apiKey,
              clientId: auth.clientId,
              before: before,
            )
          : await api.posts(
              siteUrl: instance.url,
              groupName: groupName,
              apiKey: auth.apiKey,
              clientId: auth.clientId,
              before: before,
            );
      _commit(token, () {
        final rows = more ? [...held.posts] : <GroupActivityPost>[];
        final seen = {for (final post in rows) post.id};
        for (final post in page.posts) {
          if (seen.add(post.id)) rows.add(post);
        }
        _activities[key] = GroupActivityState(
          posts: List.unmodifiable(rows),
          hasMore: page.hasMore,
          loaded: true,
        );
      });
    } catch (error, stackTrace) {
      _fail(token, 'groups.activity', error, stackTrace, () {
        _activities[key] = GroupActivityState(
          posts: held.posts,
          hasMore: held.hasMore,
          loaded: true,
          error: more
              ? "Couldn't load more activity."
              : "Couldn't load group activity.",
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
    final key = _groupKey(instance.url, groupName);
    final requestKey = ('permissions', key);
    final held = permissionsState(instance.url, groupName);
    if (_requests.containsKey(requestKey) || (!refresh && held.loaded)) return;
    final token = _start(requestKey, instance.url);
    _permissions[key] = GroupPermissionsState(
      permissions: held.permissions,
      loading: true,
      loaded: held.loaded,
    );
    notifySafely();
    try {
      final auth = await _credentialsFor(instance, token);
      if (auth == null) return;
      final rows = await api.permissions(
        siteUrl: instance.url,
        apiKey: auth.apiKey,
        clientId: auth.clientId,
        groupName: groupName,
      );
      _commit(token, () {
        _permissions[key] = GroupPermissionsState(
          permissions: rows,
          loaded: true,
        );
      });
    } catch (error, stackTrace) {
      _fail(token, 'groups.permissions', error, stackTrace, () {
        _permissions[key] = GroupPermissionsState(
          permissions: held.permissions,
          loaded: true,
          error: "Couldn't load group permissions.",
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
    final key = _groupKey(instance.url, groupName);
    final requestKey = ('logs', key);
    final held = logsState(instance.url, groupName);
    if (_requests.containsKey(requestKey) ||
        (!refresh && !more && held.loaded) ||
        (more && (!held.loaded || !held.hasMore))) {
      return;
    }
    final token = _start(requestKey, instance.url);
    _logs[key] = GroupLogsState(
      logs: held.logs,
      nextPage: held.nextPage,
      hasMore: held.hasMore,
      loading: !more,
      loadingMore: more,
      loaded: held.loaded,
    );
    notifySafely();
    try {
      final auth = await _requiredCredentials(instance, token);
      if (auth == null) return;
      final page = await api.logs(
        siteUrl: instance.url,
        apiKey: auth.apiKey!,
        clientId: auth.clientId,
        groupName: groupName,
        offset: more ? held.nextPage : 0,
      );
      _commit(token, () {
        _logs[key] = GroupLogsState(
          logs: List.unmodifiable([if (more) ...held.logs, ...page.logs]),
          nextPage: (more ? held.nextPage : 0) + 1,
          hasMore: !page.allLoaded,
          loaded: true,
        );
      });
    } catch (error, stackTrace) {
      _fail(token, 'groups.logs', error, stackTrace, () {
        _logs[key] = GroupLogsState(
          logs: held.logs,
          nextPage: held.nextPage,
          hasMore: held.hasMore,
          loaded: true,
          error: more
              ? "Couldn't load more group logs."
              : "Couldn't load group logs.",
          pageError: more,
        );
      });
    } finally {
      _finish(token);
    }
  }

  Future<bool> join(DiscourseInstance instance, Group group) => _mutate(
    instance,
    group,
    'groups.join',
    (apiKey, clientId) => api.join(
      siteUrl: instance.url,
      apiKey: apiKey,
      clientId: clientId,
      groupId: group.id,
    ),
  );

  Future<bool> leave(DiscourseInstance instance, Group group) => _mutate(
    instance,
    group,
    'groups.leave',
    (apiKey, clientId) => api.leave(
      siteUrl: instance.url,
      apiKey: apiKey,
      clientId: clientId,
      groupId: group.id,
    ),
  );

  Future<bool> requestMembership(
    DiscourseInstance instance,
    Group group,
    String reason,
  ) => _mutate(instance, group, 'groups.requestMembership', (
    apiKey,
    clientId,
  ) async {
    await api.requestMembership(
      siteUrl: instance.url,
      apiKey: apiKey,
      clientId: clientId,
      groupName: group.name,
      reason: reason,
    );
  });

  Future<bool> handleRequest(
    DiscourseInstance instance,
    Group group,
    GroupRequester requester, {
    required bool accept,
  }) async {
    final result = await _mutate(
      instance,
      group,
      accept ? 'groups.requests.accept' : 'groups.requests.deny',
      (apiKey, clientId) => api.handleMembershipRequest(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
        userId: requester.id,
        accept: accept,
      ),
      refreshDetail: false,
    );
    if (result) {
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
        _requesters[key] = GroupRequestersState(
          requesters: rows,
          total: held.total > 0 ? held.total - 1 : 0,
          nextOffset: held.nextOffset,
          hasMore: held.hasMore,
          loaded: true,
        );
      }
      notifySafely();
    }
    return result;
  }

  Future<GroupMembershipMutationResult?> addMembers(
    DiscourseInstance instance,
    Group group, {
    Iterable<String> usernames = const [],
    Iterable<String> emails = const [],
    String filter = '',
    String? order,
    bool ascending = true,
  }) async {
    GroupMembershipMutationResult? output;
    final saved = await _mutate(instance, group, 'groups.members.add', (
      apiKey,
      clientId,
    ) async {
      output = await api.addMembers(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
        usernames: usernames,
        emails: emails,
      );
    });
    if (!saved) return null;
    await loadMembers(
      instance,
      group.name,
      filter: filter,
      order: order,
      ascending: ascending,
      refresh: true,
    );
    return output;
  }

  Future<GroupInvite?> createInvite(
    DiscourseInstance instance,
    Group group, {
    String? email,
    String? customMessage,
    int maxRedemptionsAllowed = 1,
    DateTime? expiresAt,
  }) async {
    GroupInvite? output;
    final saved = await _mutate(instance, group, 'groups.invite', (
      apiKey,
      clientId,
    ) async {
      output = await api.createInvite(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
        email: email,
        customMessage: customMessage,
        maxRedemptionsAllowed: maxRedemptionsAllowed,
        expiresAt: expiresAt,
      );
    }, refreshDetail: false);
    return saved ? output : null;
  }

  Future<bool> removeMember(
    DiscourseInstance instance,
    Group group,
    GroupMember member,
  ) async {
    final saved = await _mutate(
      instance,
      group,
      'groups.members.remove',
      (apiKey, clientId) => api.removeMembers(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
        userIds: [member.id],
      ),
    );
    if (saved) {
      _members.updateAll((key, held) {
        if (key.siteUrl != instance.url ||
            key.groupName != _normalize(group.name)) {
          return held;
        }
        final rows = held.members
            .where((item) => item.id != member.id)
            .toList(growable: false);
        return GroupMembersState(
          members: rows,
          total: held.total > 0 ? held.total - 1 : 0,
          nextOffset: held.nextOffset,
          hasMore: held.hasMore,
          loaded: true,
        );
      });
      notifySafely();
    }
    return saved;
  }

  Future<bool> setMemberOwner(
    DiscourseInstance instance,
    Group group,
    GroupMember member, {
    required bool owner,
  }) async {
    final saved = await _mutate(
      instance,
      group,
      owner ? 'groups.members.makeOwner' : 'groups.members.removeOwner',
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
    if (saved) _updateMember(instance, group, member, owner: owner);
    return saved;
  }

  Future<bool> setMemberPrimary(
    DiscourseInstance instance,
    Group group,
    GroupMember member, {
    required bool primary,
  }) async {
    final saved = await _mutate(
      instance,
      group,
      primary ? 'groups.members.makePrimary' : 'groups.members.removePrimary',
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
    if (saved) _updateMember(instance, group, member, primary: primary);
    return saved;
  }

  Future<bool> deleteGroup(DiscourseInstance instance, Group group) async {
    final saved = await _mutate(
      instance,
      group,
      'groups.delete',
      (apiKey, clientId) => api.deleteGroup(
        siteUrl: instance.url,
        apiKey: apiKey,
        clientId: clientId,
        groupId: group.id,
      ),
      refreshDetail: false,
    );
    if (!saved) return false;
    final normalized = _normalize(group.name);
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
    return true;
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

  Future<bool> updateGroup(
    DiscourseInstance instance,
    Group group,
    Map<String, Object?> values, {
    bool updateExistingUsers = false,
  }) => _mutate(instance, group, 'groups.update', (apiKey, clientId) async {
    await api.updateGroup(
      siteUrl: instance.url,
      apiKey: apiKey,
      clientId: clientId,
      groupId: group.id,
      values: values,
      updateExistingUsers: updateExistingUsers,
    );
  });

  Future<bool> _mutate(
    DiscourseInstance instance,
    Group group,
    String operation,
    Future<void> Function(String apiKey, String clientId) write, {
    bool refreshDetail = true,
  }) async {
    final key = _groupKey(instance.url, group.name);
    if (isDisposed || _mutations.containsKey(key)) return false;
    final token = Object();
    final lease = lifecycle.capture(instance.url);
    _mutations[key] = token;
    final held = detailState(instance.url, group.name);
    _details[key] = GroupDetailState(
      detail: held.detail,
      loaded: held.loaded,
      mutating: true,
    );
    notifySafely();
    try {
      final apiKey = await credentials.apiKeyFor(instance.url);
      if (apiKey == null ||
          isDisposed ||
          !lease.isCurrent ||
          !identical(_mutations[key], token)) {
        return false;
      }
      final clientId = await credentials.clientId();
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_mutations[key], token)) {
        return false;
      }
      await write(apiKey, clientId);
      if (isDisposed ||
          !lease.isCurrent ||
          !identical(_mutations[key], token)) {
        return false;
      }
      _details[key] = GroupDetailState(
        detail: held.detail,
        loaded: held.loaded,
      );
      if (refreshDetail) {
        _requests.remove(key);
        await loadDetail(instance, group.name, refresh: true);
      }
      return true;
    } catch (error, stackTrace) {
      if (lease.isCurrent && identical(_mutations[key], token)) {
        _report(error, stackTrace, operation);
        _details[key] = GroupDetailState(
          detail: held.detail,
          loaded: held.loaded,
          error: "Couldn't save that group change.",
        );
      }
      return false;
    } finally {
      if (!isDisposed && identical(_mutations[key], token)) {
        _mutations.remove(key);
        notifySafely();
      }
    }
  }

  void forget(String siteUrl) {
    _directories.removeWhere((key, _) => key.siteUrl == siteUrl);
    _details.removeWhere((key, _) => key.siteUrl == siteUrl);
    _members.removeWhere((key, _) => key.siteUrl == siteUrl);
    _requesters.removeWhere((key, _) => key.siteUrl == siteUrl);
    _activities.removeWhere((key, _) => key.siteUrl == siteUrl);
    _permissions.removeWhere((key, _) => key.siteUrl == siteUrl);
    _logs.removeWhere((key, _) => key.siteUrl == siteUrl);
    _presentedDirectoryQueries.remove(siteUrl);
    _mutations.removeWhere((key, _) => key.siteUrl == siteUrl);
    _requests.removeWhere((key, _) => _requestSite[key] == siteUrl);
    _requestSite.removeWhere((_, value) => value == siteUrl);
    notifySafely();
  }

  final Map<Object, String> _requestSite = {};

  ({Object key, Object token, SiteLease lease}) _start(
    Object key,
    String siteUrl,
  ) {
    final token = Object();
    _requests[key] = token;
    _requestSite[key] = siteUrl;
    return (key: key, token: token, lease: lifecycle.capture(siteUrl));
  }

  bool _current(({Object key, Object token, SiteLease lease}) request) =>
      !isDisposed &&
      request.lease.isCurrent &&
      identical(_requests[request.key], request.token);

  Future<_GroupCredentials?> _credentialsFor(
    DiscourseInstance instance,
    ({Object key, Object token, SiteLease lease}) request,
  ) async {
    if (!instance.isConnected) {
      return _current(request) ? (apiKey: null, clientId: null) : null;
    }
    final key = await credentials.apiKeyFor(instance.url);
    if (!_current(request)) return null;
    if (key == null) return (apiKey: null, clientId: null);
    final clientId = await credentials.clientId();
    return _current(request) ? (apiKey: key, clientId: clientId) : null;
  }

  Future<_GroupCredentials?> _requiredCredentials(
    DiscourseInstance instance,
    ({Object key, Object token, SiteLease lease}) request,
  ) async {
    final auth = await _credentialsFor(instance, request);
    if (auth == null || auth.apiKey != null) return auth;
    throw StateError('This group page requires a connected account.');
  }

  void _commit(
    ({Object key, Object token, SiteLease lease}) request,
    VoidCallback mutation,
  ) {
    if (!_current(request)) return;
    request.lease.commit(() {
      if (!_current(request)) return;
      mutation();
      notifySafely();
    });
  }

  void _fail(
    ({Object key, Object token, SiteLease lease}) request,
    String operation,
    Object error,
    StackTrace stackTrace,
    VoidCallback mutation,
  ) {
    if (!_current(request)) return;
    _report(error, stackTrace, operation);
    _commit(request, mutation);
  }

  void _finish(({Object key, Object token, SiteLease lease}) request) {
    if (identical(_requests[request.key], request.token)) {
      _requests.remove(request.key);
      _requestSite.remove(request.key);
    }
  }

  void _report(Object error, StackTrace stackTrace, String operation) {
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: operation,
      source: 'groups',
      handled: true,
      degraded: true,
    );
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
    _requests.clear();
    _requestSite.clear();
    _mutations.clear();
    super.dispose();
  }
}
