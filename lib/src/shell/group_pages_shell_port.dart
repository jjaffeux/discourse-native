import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/groups_api.dart';
import '../models/content_route.dart';
import '../models/discourse_instance.dart';
import '../models/found_user.dart';
import '../models/group.dart';
import '../models/group_route.dart';
import '../models/topic_feed.dart';
import '../plugin_api/plugin_data.dart';
import 'external_link.dart';
import 'group_page.dart';
import 'group_pages_coordinator.dart';
import 'group_pages_port.dart';
import 'groups_controller.dart';
import 'shell_controller.dart';
import 'user_card.dart';

/// Adapts the shell facade at the Groups composition boundary.
///
/// Widgets and the coordinator consume [GroupPagesPort], so neither needs a
/// build-context lookup or access to the full shell facade.
final class ShellGroupPagesPort implements GroupPagesPort {
  ShellGroupPagesPort(ShellController shell)
    : _shell = shell,
      changes = Listenable.merge([shell.groups, shell.topicFeeds]);

  final ShellController _shell;

  @override
  final Listenable changes;

  DiscourseInstance? _instance(GroupPagesOwner owner) {
    if (!isCurrent(owner)) return null;
    return _shell.currentInstance;
  }

  @override
  bool isCurrent(GroupPagesOwner owner) =>
      _shell.currentInstance?.url == owner.siteUrl &&
      _shell.currentAccountIdentity == owner.accountIdentity &&
      _shell.activeTabId == owner.tabId;

  @override
  String? usernameFor(GroupPagesOwner owner) =>
      _instance(owner)?.user?.username;

  @override
  Future<void> loadDirectory(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query, {
    required bool refresh,
    required bool more,
  }) async {
    final instance = _instance(owner);
    if (instance == null) return;
    await _shell.groups.loadDirectory(
      instance,
      GroupDirectoryQuery(filter: query.filter, type: query.type),
      refresh: refresh,
      more: more,
    );
  }

  @override
  Future<void> loadDetail(
    GroupPagesOwner owner,
    GroupRoute route, {
    required bool refresh,
  }) async {
    final instance = _instance(owner);
    final groupName = route.groupName;
    if (instance == null || groupName == null) return;
    await _shell.groups.loadDetail(instance, groupName, refresh: refresh);
  }

  @override
  Future<void> loadSection(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery, {
    required bool refresh,
    required bool more,
  }) async {
    final instance = _instance(owner);
    final groupName = route.groupName;
    if (instance == null || groupName == null || route.isPlugin) return;
    switch (route.section) {
      case GroupRoute.members:
        await _shell.groups.loadMembers(
          instance,
          groupName,
          filter: memberQuery.filter,
          order: memberQuery.order,
          ascending: memberQuery.ascending,
          refresh: refresh,
          more: more,
        );
        break;
      case GroupRoute.activity:
        final detail = _shell.groups
            .detailState(owner.siteUrl, groupName)
            .detail;
        final subsection =
            route.subsection ??
            (detail?.group.canSeeMembers == true
                ? GroupRoute.posts
                : GroupRoute.mentions);
        if (subsection == GroupRoute.posts ||
            subsection == GroupRoute.mentions) {
          await _shell.groups.loadActivity(
            instance,
            groupName,
            mentions: subsection == GroupRoute.mentions,
            refresh: refresh,
            more: more,
          );
        }
        break;
      case GroupRoute.requests:
        await _shell.groups.loadRequesters(
          instance,
          groupName,
          refresh: refresh,
          more: more,
        );
        break;
      case GroupRoute.permissions:
        await _shell.groups.loadPermissions(
          instance,
          groupName,
          refresh: refresh,
        );
        break;
      case GroupRoute.manage when route.subsection == GroupRoute.logs:
        await _shell.groups.loadLogs(
          instance,
          groupName,
          refresh: refresh,
          more: more,
        );
        break;
      default:
        break;
    }
  }

  @override
  GroupDirectoryState directoryState(
    GroupPagesOwner owner,
    GroupPagesDirectoryQuery query,
  ) => _shell.groups.directoryState(
    owner.siteUrl,
    GroupDirectoryQuery(filter: query.filter, type: query.type),
  );

  @override
  GroupPageData groupData(
    GroupPagesOwner owner,
    GroupRoute route,
    GroupPagesMemberQuery memberQuery,
  ) {
    final groupName = route.groupName!;
    final detail = _shell.groups.detailState(owner.siteUrl, groupName);
    final members = _shell.groups.membersState(
      owner.siteUrl,
      groupName,
      filter: memberQuery.filter,
      order: memberQuery.order,
      ascending: memberQuery.ascending,
    );
    final requesters = _shell.groups.requestersState(owner.siteUrl, groupName);
    final subsection =
        route.subsection ??
        (detail.detail?.group.canSeeMembers == true
            ? GroupRoute.posts
            : GroupRoute.mentions);
    final activity = _shell.groups.activityState(
      owner.siteUrl,
      groupName,
      mentions: subsection == GroupRoute.mentions,
    );
    final permissions = _shell.groups.permissionsState(
      owner.siteUrl,
      groupName,
    );
    final logs = _shell.groups.logsState(owner.siteUrl, groupName);
    final user = _instance(owner)?.user;
    final config = _shell.siteConfigFor(owner.siteUrl);

    final sectionLoading = switch (route.section) {
      GroupRoute.members => members.loading,
      GroupRoute.activity => activity.loading,
      GroupRoute.requests => requesters.loading,
      GroupRoute.permissions => permissions.loading,
      GroupRoute.manage when route.subsection == GroupRoute.logs =>
        logs.loading,
      _ => false,
    };
    final loadingMore = switch (route.section) {
      GroupRoute.members => members.loadingMore,
      GroupRoute.activity => activity.loadingMore,
      GroupRoute.requests => requesters.loadingMore,
      GroupRoute.manage when route.subsection == GroupRoute.logs =>
        logs.loadingMore,
      _ => false,
    };
    final hasMore = switch (route.section) {
      GroupRoute.members => members.hasMore,
      GroupRoute.activity => activity.hasMore,
      GroupRoute.requests => requesters.hasMore,
      GroupRoute.manage when route.subsection == GroupRoute.logs =>
        logs.hasMore,
      _ => false,
    };
    final sectionError = switch (route.section) {
      GroupRoute.members => members.error,
      GroupRoute.activity => activity.error,
      GroupRoute.requests => requesters.error,
      GroupRoute.permissions => permissions.error,
      GroupRoute.manage when route.subsection == GroupRoute.logs => logs.error,
      _ => null,
    };

    return GroupPageData(
      detail: detail.detail,
      members: members.loaded
          ? GroupMembersPage(
              members: members.members,
              total: members.total,
              limit: GroupsApi.defaultMemberPageSize,
              offset: 0,
            )
          : null,
      requesters: requesters.loaded
          ? GroupRequestersPage(
              requesters: requesters.requesters,
              total: requesters.total,
              limit: GroupsApi.defaultMemberPageSize,
              offset: 0,
            )
          : null,
      activity: activity.loaded
          ? GroupActivityPage(
              posts: activity.posts,
              rawPostCount: activity.hasMore
                  ? GroupActivityPage.pageSize
                  : activity.posts.length,
            )
          : null,
      permissions: permissions.permissions,
      logs: logs.loaded
          ? GroupLogsPage(logs: logs.logs, allLoaded: !logs.hasMore)
          : null,
      currentUserData: user?.plugins ?? PluginData.none,
      canSendPrivateMessages: user?.canSendPrivateMessages == true,
      canInviteToForum: user?.canInviteToForum == true,
      currentUserStaff: user?.staff == true,
      isAdmin: user?.admin == true,
      memberFilter: memberQuery.filter,
      memberOrder: memberQuery.order,
      memberAscending: memberQuery.ascending,
      mentionsEnabled: config.mentionsEnabled,
      smtpEnabled: config.smtpEnabled,
      taggingEnabled: config.taggingEnabled,
      loading: detail.loading,
      sectionLoading: sectionLoading,
      loadingMore: loadingMore,
      mutating: detail.mutating,
      saving: detail.mutating,
      loaded: detail.loaded,
      error: detail.error,
      sectionError: sectionError,
      hasMore: hasMore,
    );
  }

  @override
  TopicFeed? topicFeed(GroupPagesOwner owner, String routeId) =>
      isCurrent(owner)
      ? _shell.topicFeeds.feedFor(owner.siteUrl, routeId)
      : null;

  @override
  bool canCreateGroup(GroupPagesOwner owner) =>
      _instance(owner)?.user?.canCreateGroup == true;

  @override
  void openGroup(GroupPagesOwner owner, String groupName) {
    if (!isCurrent(owner)) return;
    _shell.openGroupUrl(Uri(pathSegments: ['g', groupName]).path);
  }

  @override
  void createGroup(GroupPagesOwner owner) {
    if (!isCurrent(owner)) return;
    unawaited(openExternalLink('${owner.siteUrl}/g/custom/new'));
  }

  @override
  void selectRoute(GroupRoute route, {String? feedPath}) =>
      _shell.selectGroupRoute(route, feedPath: feedPath);

  @override
  void replaceWithGroup(String groupName) => _shell.replaceCurrentContent(
    ContentRoute.group(GroupRoute.detail(groupName)),
  );

  @override
  void replaceWithDirectory() => _shell.replaceCurrentContent(
    ContentRoute.group(const GroupRoute.directory()),
  );

  @override
  bool handleBack({required bool canReturnToSidebar}) =>
      _shell.handleBack(canReturnToSidebar: canReturnToSidebar);

  @override
  Future<bool> join(GroupPagesOwner owner, Group group) async {
    final instance = _instance(owner);
    return instance != null && await _shell.groups.join(instance, group);
  }

  @override
  Future<bool> leave(GroupPagesOwner owner, Group group) async {
    final instance = _instance(owner);
    return instance != null && await _shell.groups.leave(instance, group);
  }

  @override
  Future<bool> requestMembership(
    GroupPagesOwner owner,
    Group group,
    String reason,
  ) async {
    final instance = _instance(owner);
    return instance != null &&
        await _shell.groups.requestMembership(instance, group, reason);
  }

  @override
  Future<bool> deleteGroup(GroupPagesOwner owner, Group group) async {
    final instance = _instance(owner);
    return instance != null && await _shell.groups.deleteGroup(instance, group);
  }

  @override
  Future<List<FoundUser>> searchUsers(GroupPagesOwner owner, String query) =>
      isCurrent(owner)
      ? _shell.searchUsers(siteUrl: owner.siteUrl, topicId: null, term: query)
      : Future.value(const []);

  @override
  Future<GroupMembershipMutationResult?> addMembers(
    GroupPagesOwner owner,
    Group group,
    List<String> usernames,
    List<String> emails,
    GroupPagesMemberQuery memberQuery,
  ) async {
    final instance = _instance(owner);
    if (instance == null) return null;
    return _shell.groups.addMembers(
      instance,
      group,
      usernames: usernames,
      emails: emails,
      filter: memberQuery.filter,
      order: memberQuery.order,
      ascending: memberQuery.ascending,
    );
  }

  @override
  Future<GroupInvite?> createInvite(
    GroupPagesOwner owner,
    Group group, {
    String? email,
    String? customMessage,
  }) async {
    final instance = _instance(owner);
    if (instance == null) return null;
    return _shell.groups.createInvite(
      instance,
      group,
      email: email,
      customMessage: customMessage,
    );
  }

  @override
  Future<bool> memberAction(
    GroupPagesOwner owner,
    Group group,
    GroupMember member,
    GroupMemberAction action,
  ) async {
    final instance = _instance(owner);
    if (instance == null) return false;
    return switch (action) {
      GroupMemberAction.remove => _shell.groups.removeMember(
        instance,
        group,
        member,
      ),
      GroupMemberAction.makeOwner => _shell.groups.setMemberOwner(
        instance,
        group,
        member,
        owner: true,
      ),
      GroupMemberAction.removeOwner => _shell.groups.setMemberOwner(
        instance,
        group,
        member,
        owner: false,
      ),
      GroupMemberAction.makePrimary => _shell.groups.setMemberPrimary(
        instance,
        group,
        member,
        primary: true,
      ),
      GroupMemberAction.removePrimary => _shell.groups.setMemberPrimary(
        instance,
        group,
        member,
        primary: false,
      ),
    };
  }

  @override
  void messageGroup(GroupPagesOwner owner, Group group) {
    if (!isCurrent(owner)) return;
    _shell.openPrivateMessage(
      siteUrl: owner.siteUrl,
      targetRecipients: group.name,
    );
  }

  @override
  void openMember(
    BuildContext context,
    GroupPagesOwner owner,
    GroupMember member,
  ) {
    if (!isCurrent(owner)) return;
    unawaited(
      showUserCard(
        context: context,
        username: member.username,
        siteUrl: owner.siteUrl,
      ),
    );
  }

  @override
  void openActivityPost(GroupPagesOwner owner, GroupActivityPost post) {
    if (!isCurrent(owner)) return;
    _shell.openTopicPost(
      siteUrl: owner.siteUrl,
      topicId: post.topicId,
      postNumber: post.postNumber,
    );
  }

  @override
  Future<void> handleRequest(
    GroupPagesOwner owner,
    Group group,
    GroupRequester requester,
    GroupRequestAction action,
  ) async {
    final instance = _instance(owner);
    if (instance == null) return;
    await _shell.groups.handleRequest(
      instance,
      group,
      requester,
      accept: action == GroupRequestAction.accept,
    );
  }

  @override
  Future<void> saveManage(
    GroupPagesOwner owner,
    Group group,
    GroupManageUpdate update,
  ) async {
    final instance = _instance(owner);
    if (instance == null) return;
    await _shell.groups.updateGroup(instance, group, update.values);
  }
}
