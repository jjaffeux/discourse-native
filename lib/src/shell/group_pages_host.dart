import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_route.dart';
import '../plugin_api/plugin_registry.dart';
import 'adaptive_dialog_action.dart';
import 'group_page.dart';
import 'group_pages_coordinator.dart';
import 'group_pages_port.dart';
import 'groups_controller.dart';
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
          key: ValueKey(owner),
          loadMemberPreview: (group) => port.loadMemberPreview(owner, group),
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
        // As on the web, only a group anyone can join again is left without
        // asking first.
        if (!group.publicAdmission) {
          final confirmed = await showDiscourseAlertDialog<bool>(
            context: context,
            title: Text('Leave ${group.label}?'),
            description: const Text(
              "You won't be able to join it again on your own.",
            ),
            cancelLabel: const Text('Cancel'),
            actionLabel: const Text('Leave group'),
            cancelResult: false,
            actionResult: true,
            actionKey: const ValueKey('confirm-leave-group'),
            actionVariant: DButtonVariant.destructive,
          );
          if (confirmed != true || !context.mounted) return;
        }
        await port.leave(owner, group);
        break;
      case GroupMembershipAction.request:
        final navigationIdentity = coordinator.navigationIdentity;
        final reason = await showDDialog<String>(
          context: context,
          builder: (context, controller) =>
              _MembershipRequestDialog(group: group, controller: controller),
        );
        if (reason == null || reason.trim().isEmpty) return;
        final result = await port.requestMembership(owner, group, reason);
        if (!context.mounted) return;
        switch (result) {
          // Discourse files the request as a private message to the group's
          // owners; the web client routes there, and so does the page that
          // sent it, unless it has since been left.
          case GroupMembershipRequestSent(:final messageUrl?)
              when identical(
                coordinator.navigationIdentity,
                navigationIdentity,
              ):
            port.openMembershipRequest(owner, messageUrl);
          case GroupMembershipRequestFailed(:final message):
            DToast.show(context, message, type: DToastType.error);
          case GroupMembershipRequestSent() || null:
            break;
        }
    }
  }

  // Asked as the web's save asks; either answer saves the change, while
  // dismissing the question saves nothing.
  Future<bool?> _applyToExistingUsers(BuildContext context, int userCount) {
    if (!context.mounted) return Future.value();
    final members = userCount == 1 ? 'member' : 'members';
    return showDiscourseAlertDialog<bool>(
      context: context,
      title: const Text('Update existing members?'),
      description: Text(
        'This change also affects the notification preferences of '
        '$userCount existing $members. Apply it to them too?',
      ),
      cancelLabel: const Text('Only new members'),
      actionLabel: Text('Update $userCount $members'),
      cancelResult: false,
      actionResult: true,
      cancelKey: const ValueKey('keep-existing-member-preferences'),
      actionKey: const ValueKey('update-existing-member-preferences'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = coordinator.childIdentity!.owner;
    final route = coordinator.page.route!;
    final navigationIdentity = coordinator.navigationIdentity;
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
                  if (deleted) {
                    coordinator.showDirectory(from: navigationIdentity);
                  }
                  return deleted;
                },
          onMemberFilterChanged: (value) {
            if (coordinator.replaceMemberQuery(
              coordinator.memberQuery.copyWith(filter: value),
            )) {
              unawaited(coordinator.reloadSection());
            }
          },
          onMemberSortChanged: (order, ascending) {
            if (coordinator.replaceMemberQuery(
              coordinator.memberQuery.copyWith(
                order: order,
                ascending: ascending,
              ),
            )) {
              unawaited(coordinator.reloadSection());
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
          // Core answers `messageable` with the reader's permission to
          // message this group. It is independent of membership and of
          // whether the group has any messages yet, which decide only the
          // Messages tab, and of the reader's general private-message
          // permission, which a group messageable by everyone overrides.
          onMessageGroup:
              group != null &&
                  group.messageable &&
                  port.usernameFor(owner) != null
              ? () => port.messageGroup(owner, group)
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
              : (update) => port.saveManage(
                  owner,
                  group,
                  update,
                  applyToExistingUsers: (userCount) =>
                      _applyToExistingUsers(context, userCount),
                ),
        );
      },
    );
  }
}

/// Owns the reason field, so the field outlives the dialog's exit transition
/// rather than being disposed while the closing route still draws it.
class _MembershipRequestDialog extends StatefulWidget {
  const _MembershipRequestDialog({
    required this.group,
    required this.controller,
  });

  final Group group;
  final DDialogController<String> controller;

  @override
  State<_MembershipRequestDialog> createState() =>
      _MembershipRequestDialogState();
}

class _MembershipRequestDialogState extends State<_MembershipRequestDialog> {
  late final TextEditingController _reason = TextEditingController(
    text: widget.group.membershipRequestTemplate,
  );

  // Discourse requires a reason, and the web form holds its submit until one
  // is written.
  bool get _canSend => _reason.text.trim().isNotEmpty;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DDialogContent(
    key: const ValueKey('group-request-dialog'),
    semanticLabel: 'Request to join ${widget.group.label}',
    maxWidth: 460,
    children: [
      DDialogHeader(
        children: [
          DDialogTitle(child: Text('Request to join ${widget.group.label}')),
        ],
      ),
      DTextarea(
        controller: _reason,
        minLines: 3,
        maxLines: 8,
        autofocus: true,
        labelText: 'Reason',
        onChanged: (_) => setState(() {}),
      ),
      DDialogFooter(
        children: [
          DButton(
            label: const Text('Cancel'),
            variant: DButtonVariant.outline,
            onPressed: widget.controller.close,
          ),
          DButton(
            key: const ValueKey('send-group-request'),
            label: const Text('Send request'),
            variant: DButtonVariant.primary,
            onPressed: _canSend
                ? () => widget.controller.close(_reason.text)
                : null,
          ),
        ],
      ),
    ],
  );
}
