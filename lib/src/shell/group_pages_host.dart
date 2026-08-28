import 'dart:async';

import 'package:flutter/material.dart';

import '../data/groups_api.dart';
import '../models/group.dart';
import '../models/group_route.dart';
import '../plugin_api/plugin_data.dart';
import '../plugin_api/plugin_registry.dart';
import 'group_page.dart';
import 'groups_controller.dart';
import 'groups_page.dart';
import 'message_inbox_page.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_list_view.dart';

/// Connects the presentation-only directory widget to the shell's independent
/// group cache.
class GroupsDirectoryHost extends StatefulWidget {
  const GroupsDirectoryHost({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<GroupsDirectoryHost> createState() => _GroupsDirectoryHostState();
}

class _GroupsDirectoryHostState extends State<GroupsDirectoryHost> {
  GroupDirectoryQuery _query = const GroupDirectoryQuery();
  bool _loadScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(GroupsDirectoryHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) _scheduleLoad();
  }

  void _scheduleLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted) return;
      final shell = ShellScope.read(context);
      final instance = shell.currentInstance;
      if (instance?.url == widget.siteUrl) {
        unawaited(shell.groups.loadDirectory(instance!, _query));
      }
    });
  }

  Future<void> _load({bool refresh = false, bool more = false}) async {
    final shell = ShellScope.read(context);
    final instance = shell.currentInstance;
    if (instance?.url != widget.siteUrl) return;
    await shell.groups.loadDirectory(
      instance!,
      _query,
      refresh: refresh,
      more: more,
    );
  }

  void _replaceQuery(GroupDirectoryQuery query) {
    if (query == _query) return;
    setState(() => _query = query);
    unawaited(_load(refresh: true));
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ListenableBuilder(
      listenable: shell.groups,
      builder: (context, _) {
        final state = shell.groups.directoryState(widget.siteUrl, _query);
        return GroupsPage(
          siteUrl: widget.siteUrl,
          data: GroupsPageData(
            groups: state.groups,
            typeFilters: state.typeFilters,
            totalRows: state.totalRows,
            query: _query.filter,
            type: _query.type,
            order: _query.order == GroupDirectoryOrder.memberCount.wireName
                ? GroupDirectoryOrder.memberCount
                : GroupDirectoryOrder.name,
            ascending: _query.ascending,
            loading: state.loading,
            loadingMore: state.loadingMore,
            loaded: state.loaded,
            hasMore: state.hasMore,
            error: state.error,
            pageError: state.pageError,
          ),
          onSearchChanged: (value) =>
              _replaceQuery(_query.copyWith(filter: value)),
          onTypeChanged: (value) => _replaceQuery(_query.copyWith(type: value)),
          onOrderChanged: (value) =>
              _replaceQuery(_query.copyWith(order: value.wireName)),
          onAscendingChanged: (value) =>
              _replaceQuery(_query.copyWith(ascending: value)),
          onRefresh: () => _load(refresh: true),
          onLoadMore: () => unawaited(_load(more: true)),
        );
      },
    );
  }
}

/// Connects a restored group route to its group-specific and topic-list state.
class GroupPageHost extends StatefulWidget {
  const GroupPageHost({
    super.key,
    required this.siteUrl,
    required this.route,
    required this.registry,
  });

  final String siteUrl;
  final GroupRoute route;
  final PluginRegistry registry;

  @override
  State<GroupPageHost> createState() => _GroupPageHostState();
}

class _GroupPageHostState extends State<GroupPageHost> {
  Future<void> _load(GroupRoute route, {bool refresh = false}) async {
    final shell = ShellScope.read(context);
    final instance = shell.currentInstance;
    if (instance?.url != widget.siteUrl || route.groupName == null) return;
    await shell.groups.loadDetail(
      instance!,
      route.groupName!,
      refresh: refresh,
    );
    if (!mounted || shell.currentInstance?.url != widget.siteUrl) return;
    await _loadSection(route, refresh: refresh);
  }

  Future<void> _loadSection(
    GroupRoute route, {
    bool refresh = false,
    bool more = false,
  }) async {
    final shell = ShellScope.read(context);
    final instance = shell.currentInstance;
    final groupName = route.groupName;
    if (instance?.url != widget.siteUrl ||
        groupName == null ||
        route.isPlugin) {
      return;
    }
    switch (route.section) {
      case GroupRoute.members:
        await shell.groups.loadMembers(
          instance!,
          groupName,
          refresh: refresh,
          more: more,
        );
        break;
      case GroupRoute.activity:
        final detail = shell.groups
            .detailState(widget.siteUrl, groupName)
            .detail;
        final subsection =
            route.subsection ??
            (detail?.group.canSeeMembers == true
                ? GroupRoute.posts
                : GroupRoute.mentions);
        if (subsection == GroupRoute.posts ||
            subsection == GroupRoute.mentions) {
          await shell.groups.loadActivity(
            instance!,
            groupName,
            mentions: subsection == GroupRoute.mentions,
            refresh: refresh,
            more: more,
          );
        }
        break;
      case GroupRoute.requests:
        await shell.groups.loadRequesters(
          instance!,
          groupName,
          refresh: refresh,
          more: more,
        );
        break;
      case GroupRoute.permissions:
        await shell.groups.loadPermissions(
          instance!,
          groupName,
          refresh: refresh,
        );
        break;
      case GroupRoute.manage when route.subsection == GroupRoute.logs:
        await shell.groups.loadLogs(
          instance!,
          groupName,
          refresh: refresh,
          more: more,
        );
        break;
      default:
        break;
    }
  }

  GroupPageData _data(ShellController shell) {
    final groupName = widget.route.groupName!;
    final detail = shell.groups.detailState(widget.siteUrl, groupName);
    final members = shell.groups.membersState(widget.siteUrl, groupName);
    final requesters = shell.groups.requestersState(widget.siteUrl, groupName);
    final subsection =
        widget.route.subsection ??
        (detail.detail?.group.canSeeMembers == true
            ? GroupRoute.posts
            : GroupRoute.mentions);
    final activity = shell.groups.activityState(
      widget.siteUrl,
      groupName,
      mentions: subsection == GroupRoute.mentions,
    );
    final permissions = shell.groups.permissionsState(
      widget.siteUrl,
      groupName,
    );
    final logs = shell.groups.logsState(widget.siteUrl, groupName);
    final user = shell.currentInstance?.user;
    final config = shell.siteConfigFor(widget.siteUrl);

    final sectionLoading = switch (widget.route.section) {
      GroupRoute.members => members.loading,
      GroupRoute.activity => activity.loading,
      GroupRoute.requests => requesters.loading,
      GroupRoute.permissions => permissions.loading,
      GroupRoute.manage when widget.route.subsection == GroupRoute.logs =>
        logs.loading,
      _ => false,
    };
    final loadingMore = switch (widget.route.section) {
      GroupRoute.members => members.loadingMore,
      GroupRoute.activity => activity.loadingMore,
      GroupRoute.requests => requesters.loadingMore,
      GroupRoute.manage when widget.route.subsection == GroupRoute.logs =>
        logs.loadingMore,
      _ => false,
    };
    final hasMore = switch (widget.route.section) {
      GroupRoute.members => members.hasMore,
      GroupRoute.activity => activity.hasMore,
      GroupRoute.requests => requesters.hasMore,
      GroupRoute.manage when widget.route.subsection == GroupRoute.logs =>
        logs.hasMore,
      _ => false,
    };
    final sectionError = switch (widget.route.section) {
      GroupRoute.members => members.error,
      GroupRoute.activity => activity.error,
      GroupRoute.requests => requesters.error,
      GroupRoute.permissions => permissions.error,
      GroupRoute.manage when widget.route.subsection == GroupRoute.logs =>
        logs.error,
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
      isAdmin: user?.admin == true,
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

  Widget? _topicFeed(ShellController shell, {required bool messages}) {
    final route = shell.currentContent;
    final feed = route == null
        ? null
        : shell.topicFeeds.feedFor(widget.siteUrl, route.id);
    if (feed == null) return null;
    return messages ? MessageInboxPage(feed: feed) : TopicListView(feed: feed);
  }

  Future<void> _membership(GroupMembershipAction action) async {
    final shell = ShellScope.read(context);
    final instance = shell.currentInstance;
    final group = shell.groups
        .detailState(widget.siteUrl, widget.route.groupName!)
        .detail
        ?.group;
    if (instance == null || group == null) return;
    switch (action) {
      case GroupMembershipAction.join:
        await shell.groups.join(instance, group);
        break;
      case GroupMembershipAction.leave:
        await shell.groups.leave(instance, group);
        break;
      case GroupMembershipAction.request:
        final controller = TextEditingController(
          text: group.membershipRequestTemplate,
        );
        final reason = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Request to join ${group.label}'),
            content: TextField(
              controller: controller,
              minLines: 3,
              maxLines: 8,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Send request'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (reason?.trim().isNotEmpty == true) {
          await shell.groups.requestMembership(instance, group, reason!);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell.groups, shell.topicFeeds]),
      builder: (context, _) {
        final data = _data(shell);
        final group = data.detail?.group;
        final isTopicFeed =
            widget.route.section == GroupRoute.activity &&
            widget.route.subsection == GroupRoute.topics;
        final isMessageFeed = widget.route.section == GroupRoute.messages;
        return GroupPage(
          siteUrl: widget.siteUrl,
          route: widget.route,
          registry: widget.registry,
          data: data,
          topicFeed: isTopicFeed ? _topicFeed(shell, messages: false) : null,
          messageFeed: isMessageFeed ? _topicFeed(shell, messages: true) : null,
          onLoadRequested: (route) => unawaited(_load(route)),
          onRefresh: () => _load(widget.route, refresh: true),
          onLoadMore: () => unawaited(_loadSection(widget.route, more: true)),
          onSelectRoute: shell.selectGroupRoute,
          onMembershipAction: _membership,
          onMessageGroup:
              group?.canShowMessages(
                    canSendPrivateMessages:
                        shell.currentInstance?.user?.canSendPrivateMessages ==
                        true,
                    isAdmin: shell.currentInstance?.user?.admin == true,
                  ) ==
                  true
              ? () => shell.selectGroupRoute(
                  GroupRoute.detail(
                    group!.name,
                    section: GroupRoute.messages,
                    subsection: GroupRoute.inbox,
                  ),
                )
              : null,
          onOpenActivityPost: (post) => shell.openTopicPost(
            siteUrl: widget.siteUrl,
            topicId: post.topicId,
            postNumber: post.postNumber,
          ),
          onRequestAction: group == null
              ? null
              : (requester, action) => shell.groups.handleRequest(
                  shell.currentInstance!,
                  group,
                  requester,
                  accept: action == GroupRequestAction.accept,
                ),
          onSaveManage: group == null
              ? null
              : (update) => shell.groups.updateGroup(
                  shell.currentInstance!,
                  group,
                  update.values,
                ),
        );
      },
    );
  }
}
