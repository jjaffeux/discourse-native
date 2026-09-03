import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_route.dart';
import '../plugin_api/plugin_registry.dart';
import '../theme/d_button.dart';
import 'group_page.dart';
import 'group_pages_coordinator.dart';
import 'group_pages_port.dart';
import 'groups_page.dart';
import 'topic_list_view.dart';

class GroupPagesHost extends StatefulWidget {
  const GroupPagesHost({
    super.key,
    required this.coordinator,
    required this.port,
    required this.registry,
  });

  final GroupPagesCoordinator coordinator;
  final GroupPagesPort port;
  final PluginRegistry registry;

  @override
  State<GroupPagesHost> createState() => _GroupPagesHostState();
}

class _GroupPagesHostState extends State<GroupPagesHost> {
  bool _loadScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(GroupPagesHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleLoad();
  }

  void _scheduleLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (mounted) unawaited(widget.coordinator.requestLoad());
    });
  }

  @override
  Widget build(BuildContext context) => switch (widget.coordinator.page.kind) {
    GroupPagesPageKind.directory => _GroupsDirectoryView(
      coordinator: widget.coordinator,
      port: widget.port,
    ),
    GroupPagesPageKind.detail => _GroupDetailView(
      coordinator: widget.coordinator,
      port: widget.port,
      registry: widget.registry,
    ),
    GroupPagesPageKind.unknown => const Center(
      child: Text('Unknown group route.', key: ValueKey('unknown-group-route')),
    ),
    GroupPagesPageKind.none => const SizedBox.shrink(),
  };
}

class _GroupsDirectoryView extends StatelessWidget {
  const _GroupsDirectoryView({required this.coordinator, required this.port});

  final GroupPagesCoordinator coordinator;
  final GroupPagesPort port;

  @override
  Widget build(BuildContext context) {
    final owner = coordinator.childIdentity!.owner;
    return ListenableBuilder(
      listenable: port.changes,
      builder: (context, _) {
        final query = coordinator.directoryQuery;
        final state = port.directoryState(owner, query);
        return GroupsPage(
          siteUrl: owner.siteUrl,
          data: GroupsPageData(
            groups: state.groups,
            typeFilters: state.typeFilters,
            totalRows: state.totalRows,
            query: query.filter,
            type: query.type,
            loading: state.loading,
            loadingMore: state.loadingMore,
            loaded: state.loaded,
            hasMore: state.hasMore,
            error: state.error,
            pageError: state.pageError,
            canCreateGroup: port.canCreateGroup(owner),
          ),
          onSearchChanged: (value) {
            if (coordinator.replaceDirectoryQuery(
              coordinator.directoryQuery.copyWith(filter: value),
            )) {
              unawaited(coordinator.requestLoad(refresh: true));
            }
          },
          onTypeChanged: (value) {
            final query = value == null
                ? coordinator.directoryQuery.withoutType()
                : coordinator.directoryQuery.copyWith(type: value);
            if (coordinator.replaceDirectoryQuery(query)) {
              unawaited(coordinator.requestLoad(refresh: true));
            }
          },
          onRefresh: () => coordinator.requestLoad(refresh: true),
          onLoadMore: () => unawaited(coordinator.loadMore()),
          onOpenGroup: (group) => port.openGroup(owner, group.name),
          onCreateGroup: () => port.createGroup(owner),
        );
      },
    );
  }
}

class _GroupDetailView extends StatelessWidget {
  const _GroupDetailView({
    required this.coordinator,
    required this.port,
    required this.registry,
  });

  final GroupPagesCoordinator coordinator;
  final GroupPagesPort port;
  final PluginRegistry registry;

  Future<void> _membership(
    BuildContext context,
    GroupPagesOwner owner,
    Group group,
    GroupMembershipAction action,
  ) async {
    switch (action) {
      case GroupMembershipAction.join:
        await port.join(owner, group);
        break;
      case GroupMembershipAction.leave:
        await port.leave(owner, group);
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
              DButton(
                label: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              DButton(
                label: const Text('Send request'),
                onPressed: () => Navigator.pop(context, controller.text),
                variant: DButtonVariant.primary,
              ),
            ],
          ),
        );
        controller.dispose();
        if (reason?.trim().isNotEmpty == true) {
          await port.requestMembership(owner, group, reason!);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = coordinator.childIdentity!.owner;
    final route = coordinator.page.route!;
    return ListenableBuilder(
      listenable: port.changes,
      builder: (context, _) {
        final data = port.groupData(owner, route, coordinator.memberQuery);
        final group = data.detail?.group;
        final isTopicFeed =
            route.section == GroupRoute.activity &&
            route.subsection == GroupRoute.topics;
        final isMessageFeed = route.section == GroupRoute.messages;
        final feed = port.topicFeed(owner, route.id);
        return GroupPage(
          siteUrl: owner.siteUrl,
          route: route,
          registry: registry,
          data: data,
          topicFeed: isTopicFeed && feed != null
              ? TopicListView(feed: feed)
              : null,
          messageFeed: isMessageFeed && feed != null
              ? TopicListView(feed: feed)
              : null,
          onRefresh: () => coordinator.requestLoad(refresh: true),
          onLoadMore: () => unawaited(coordinator.loadMore()),
          onSelectRoute: coordinator.selectRoute,
          onMembershipAction: group == null
              ? null
              : (action) => _membership(context, owner, group, action),
          onDeleteGroup: group == null
              ? null
              : () async {
                  final deleted = await port.deleteGroup(owner, group);
                  if (deleted) coordinator.showDirectory();
                  return deleted;
                },
          onMemberFilterChanged: (value) {
            if (coordinator.replaceMemberQuery(
              coordinator.memberQuery.copyWith(filter: value),
            )) {
              unawaited(coordinator.requestLoad(refresh: true));
            }
          },
          onMemberSortChanged: (order, ascending) {
            if (coordinator.replaceMemberQuery(
              coordinator.memberQuery.copyWith(
                order: order,
                ascending: ascending,
              ),
            )) {
              unawaited(coordinator.requestLoad(refresh: true));
            }
          },
          onSearchUsers: (query) => port.searchUsers(owner, query),
          onAddMembers: group == null
              ? null
              : (usernames, emails) => port.addMembers(
                  owner,
                  group,
                  usernames,
                  emails,
                  coordinator.memberQuery,
                ),
          onCreateInvite: group == null
              ? null
              : ({String? email, String? customMessage}) => port.createInvite(
                  owner,
                  group,
                  email: email,
                  customMessage: customMessage,
                ),
          onMemberAction: group == null
              ? null
              : (member, action) =>
                    port.memberAction(owner, group, member, action),
          onMessageGroup:
              group?.canShowMessages(
                    canSendPrivateMessages: data.canSendPrivateMessages,
                    isAdmin: data.isAdmin,
                  ) ==
                  true
              ? () => port.messageGroup(owner, group!)
              : null,
          onOpenMember: (memberContext, member) =>
              port.openMember(memberContext, owner, member),
          onOpenActivityPost: (post) => port.openActivityPost(owner, post),
          onRequestAction: group == null
              ? null
              : (requester, action) =>
                    port.handleRequest(owner, group, requester, action),
          onSaveManage: group == null
              ? null
              : (update) => port.saveManage(owner, group, update),
        );
      },
    );
  }
}
