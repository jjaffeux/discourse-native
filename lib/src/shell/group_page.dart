import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/found_user.dart';
import '../models/group.dart';
import '../models/group_route.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'category_icon.dart';
import 'command_menu.dart';
import 'content_reading_lane.dart';
import 'group/group_manage_controller.dart';
import 'group/group_members_controller.dart';
import 'group/group_page_types.dart';
import 'group_flair.dart';
import 'relative_time.dart';
import 'shell_sheet.dart';

export 'group/group_page_types.dart';

part 'group/group_activity_view.dart';
part 'group/group_manage_view.dart';
part 'group/group_members_view.dart';
part 'group/group_shared_view.dart';

const double _groupDesktopBreakpoint = 720;

@immutable
final class GroupPageData {
  const GroupPageData({
    this.detail,
    this.members,
    this.requesters,
    this.activity,
    this.permissions = const [],
    this.logs,
    this.currentUserData = PluginData.none,
    this.canSendPrivateMessages = false,
    this.canInviteToForum = false,
    this.currentUserStaff = false,
    this.isAdmin = false,
    this.memberFilter = '',
    this.memberOrder = 'last_seen_at',
    this.memberAscending = false,
    this.mentionsEnabled = true,
    this.smtpEnabled = false,
    this.taggingEnabled = true,
    this.loading = false,
    this.sectionLoading = false,
    this.loadingMore = false,
    this.mutating = false,
    this.loaded = false,
    this.error,
    this.sectionError,
    this.hasMore = false,
  });

  final GroupDetail? detail;
  final GroupMembersPage? members;
  final GroupRequestersPage? requesters;
  final GroupActivityPage? activity;
  final List<GroupPermission> permissions;
  final GroupLogsPage? logs;
  final PluginData currentUserData;
  final bool canSendPrivateMessages;
  final bool canInviteToForum;
  final bool currentUserStaff;
  final bool isAdmin;
  final String memberFilter;
  final String memberOrder;
  final bool memberAscending;
  final bool mentionsEnabled;
  final bool smtpEnabled;
  final bool taggingEnabled;
  final bool loading;
  final bool sectionLoading;
  final bool loadingMore;
  final bool mutating;
  final bool loaded;
  final String? error;
  final String? sectionError;
  final bool hasMore;
}

class GroupPage extends StatefulWidget {
  const GroupPage({
    super.key,
    required this.siteUrl,
    required this.route,
    required this.registry,
    required this.data,
    this.topicFeed,
    this.messageFeed,
    this.onRefresh,
    this.onLoadMore,
    this.onSelectRoute,
    this.onMembershipAction,
    this.onMessageGroup,
    this.onDeleteGroup,
    this.onMemberFilterChanged,
    this.onMemberSortChanged,
    this.onSearchUsers,
    this.onAddMembers,
    this.onCreateInvite,
    this.onMemberAction,
    required this.onOpenMember,
    this.onOpenActivityPost,
    this.onRequestAction,
    this.onSaveManage,
  });

  final String siteUrl;
  final GroupRoute route;
  final PluginRegistry registry;
  final GroupPageData data;
  final Widget? topicFeed;
  final Widget? messageFeed;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final ValueChanged<GroupRoute>? onSelectRoute;
  final Future<void> Function(GroupMembershipAction action)? onMembershipAction;
  final VoidCallback? onMessageGroup;
  final Future<bool> Function()? onDeleteGroup;
  final ValueChanged<String>? onMemberFilterChanged;
  final GroupMemberSortChanged? onMemberSortChanged;
  final Future<List<FoundUser>> Function(String query)? onSearchUsers;
  final GroupAddMembers? onAddMembers;
  final GroupCreateInvite? onCreateInvite;
  final GroupMemberActionCallback? onMemberAction;
  final void Function(BuildContext context, GroupMember member) onOpenMember;
  final ValueChanged<GroupActivityPost>? onOpenActivityPost;
  final Future<void> Function(
    GroupRequester requester,
    GroupRequestAction action,
  )?
  onRequestAction;
  final GroupManageSubmit? onSaveManage;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  void _select(GroupRoute route) {
    widget.onSelectRoute?.call(route);
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.data.detail;
    if (detail == null) {
      if (widget.data.error case final error?) {
        return _GroupState(
          icon: DIcons.triangleExclamation,
          title: error,
          actionLabel: 'Try again',
          onAction: widget.onRefresh,
        );
      }
      return const Center(
        child: CircularProgressIndicator.adaptive(
          key: ValueKey('group-loading'),
        ),
      );
    }

    final group = detail.group;
    final pluginContext = PluginGroupContext(
      siteUrl: widget.siteUrl,
      route: widget.route,
      groupName: group.name,
      canSeeMembers: group.canSeeMembers,
      groupData: group.plugins,
      currentUserData: widget.data.currentUserData,
    );
    final pluginTabs = _pluginTabs(pluginContext);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupHeader(
          siteUrl: widget.siteUrl,
          group: group,
          isAdmin: widget.data.isAdmin,
          mutating: widget.data.mutating,
          onMembershipAction: widget.onMembershipAction,
          onMessageGroup: widget.onMessageGroup,
          onDeleteGroup: widget.onDeleteGroup,
        ),
        _PrimaryTabs(
          route: widget.route,
          group: group,
          data: widget.data,
          pluginTabs: pluginTabs,
          onSelect: _select,
        ),
        Expanded(
          child: _sectionBody(
            context,
            group: group,
            pluginContext: pluginContext,
          ),
        ),
      ],
    );
  }

  List<_OwnedPluginTab> _pluginTabs(PluginGroupContext context) {
    return [
      for (final owned in widget.registry.ownedGroupTabs(context))
        _OwnedPluginTab(owner: owned.owner.value, tab: owned.tab),
    ];
  }

  Widget _sectionBody(
    BuildContext context, {
    required Group group,
    required PluginGroupContext pluginContext,
  }) {
    if (widget.route.isPlugin) {
      Widget buildPlugin() =>
          widget.registry.groupContent(context, pluginContext) ??
          const _GroupState(
            icon: DIcons.layerGroup,
            title: 'This group feature is unavailable.',
          );
      final listenable = widget.registry.groupListenable(
        context,
        pluginContext,
      );
      return listenable == null
          ? buildPlugin()
          : ListenableBuilder(
              listenable: listenable,
              builder: (_, _) => buildPlugin(),
            );
    }

    final body = switch (widget.route.section) {
      GroupRoute.members => _MembersSection(
        siteUrl: widget.siteUrl,
        page: widget.data.members,
        group: group,
        loading: widget.data.sectionLoading,
        loadingMore: widget.data.loadingMore,
        hasMore: widget.data.hasMore,
        error: widget.data.sectionError,
        onOpenMember: widget.onOpenMember,
        onLoadMore: widget.onLoadMore,
        filter: widget.data.memberFilter,
        order: widget.data.memberOrder,
        ascending: widget.data.memberAscending,
        currentUserStaff: widget.data.currentUserStaff,
        mutating: widget.data.mutating,
        canInviteToForum: widget.data.canInviteToForum,
        onFilterChanged: widget.onMemberFilterChanged,
        onSortChanged: widget.onMemberSortChanged,
        onSearchUsers: widget.onSearchUsers,
        onAddMembers: widget.onAddMembers,
        onCreateInvite: widget.onCreateInvite,
        onMemberAction: widget.onMemberAction,
      ),
      GroupRoute.activity => _ActivitySection(
        route: widget.route,
        group: group,
        page: widget.data.activity,
        topicFeed: widget.topicFeed,
        mentionsEnabled: widget.data.mentionsEnabled,
        loading: widget.data.sectionLoading,
        loadingMore: widget.data.loadingMore,
        hasMore: widget.data.hasMore,
        error: widget.data.sectionError,
        onSelect: _select,
        onOpenPost: widget.onOpenActivityPost,
        onLoadMore: widget.onLoadMore,
      ),
      GroupRoute.requests => _RequestsSection(
        page: widget.data.requesters,
        loading: widget.data.sectionLoading,
        mutating: widget.data.mutating,
        error: widget.data.sectionError,
        onAction: widget.onRequestAction,
        onLoadMore: widget.onLoadMore,
        hasMore: widget.data.hasMore,
      ),
      GroupRoute.messages => _MessagesSection(
        route: widget.route,
        group: group,
        content: widget.messageFeed,
        onSelect: _select,
      ),
      GroupRoute.permissions => _PermissionsSection(
        siteUrl: widget.siteUrl,
        permissions: widget.data.permissions,
        loading: widget.data.sectionLoading,
        error: widget.data.sectionError,
      ),
      GroupRoute.manage => _ManageSection(
        key: ValueKey('manage-${group.id}-${widget.route.subsection}'),
        route: widget.route,
        group: group,
        data: widget.data,
        onSelect: _select,
        onSave: widget.onSaveManage,
        onLoadMore: widget.onLoadMore,
      ),
      _ => const _GroupState(
        icon: DIcons.circleInfo,
        title: 'Unknown group section.',
      ),
    };

    if (widget.data.sectionError == null ||
        _sectionHasNoConfirmedContent(widget.route, widget.data)) {
      return body;
    }
    return Column(
      children: [
        _InlineError(message: widget.data.sectionError!),
        Expanded(child: body),
      ],
    );
  }
}

bool _sectionHasNoConfirmedContent(GroupRoute route, GroupPageData data) =>
    switch (route.section) {
      GroupRoute.members => data.members == null,
      GroupRoute.activity => data.activity == null,
      GroupRoute.requests => data.requesters == null,
      GroupRoute.permissions => data.permissions.isEmpty,
      GroupRoute.manage when route.subsection == GroupRoute.logs =>
        data.logs == null,
      _ => false,
    };

@immutable
final class _OwnedPluginTab {
  const _OwnedPluginTab({required this.owner, required this.tab});

  final String owner;
  final PluginGroupTab tab;
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.siteUrl,
    required this.group,
    required this.isAdmin,
    required this.mutating,
    required this.onMembershipAction,
    required this.onMessageGroup,
    required this.onDeleteGroup,
  });

  final String siteUrl;
  final Group group;
  final bool isAdmin;
  final bool mutating;
  final Future<void> Function(GroupMembershipAction action)? onMembershipAction;
  final VoidCallback? onMessageGroup;
  final Future<bool> Function()? onDeleteGroup;

  Future<void> _deleteGroup(BuildContext context) async {
    if (await _confirmDeleteGroup(context, group) != true) return;
    final deleted = await onDeleteGroup?.call() ?? false;
    if (context.mounted && !deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The group could not be deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membershipAction = group.isGroupUser
        ? group.publicExit
              ? GroupMembershipAction.leave
              : null
        : group.publicAdmission
        ? GroupMembershipAction.join
        : group.allowMembershipRequests
        ? GroupMembershipAction.request
        : null;
    final actionLabel = switch (membershipAction) {
      GroupMembershipAction.join => 'Join group',
      GroupMembershipAction.leave => 'Leave group',
      GroupMembershipAction.request => 'Request to join',
      null => null,
    };

    final canDelete = isAdmin && !group.automatic && onDeleteGroup != null;
    const overflowButtonSize = DButtonSize.small;
    final actionButtonHeight = DButton.iconOnlyDimensionFor(overflowButtonSize);

    return Material(
      color: theme.colorScheme.surface,
      child: ContentReadingLaneBox(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                ContentReadingLane.breakpointWidthOf(
                  context,
                  constraints.maxWidth,
                ) <
                _groupDesktopBreakpoint;
            final actions = Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (actionLabel != null)
                  SizedBox(
                    height: actionButtonHeight,
                    child: DButton(
                      key: ValueKey('group-${membershipAction!.name}'),
                      label: Text(actionLabel),
                      icon: membershipAction == GroupMembershipAction.leave
                          ? const DIcon(DIcons.xmark, size: 16)
                          : const DIcon(DIcons.userPlus, size: 16),
                      loading: mutating,
                      variant: membershipAction == GroupMembershipAction.leave
                          ? DButtonVariant.standard
                          : DButtonVariant.primary,
                      onPressed: onMembershipAction == null
                          ? null
                          : () => unawaited(
                              onMembershipAction!(membershipAction),
                            ),
                    ),
                  ),
                if (group.messageable && onMessageGroup != null)
                  SizedBox(
                    height: actionButtonHeight,
                    child: DButton(
                      key: const ValueKey('group-message'),
                      icon: const DIcon(DIcons.envelope, size: 16),
                      label: const Text('Message'),
                      onPressed: onMessageGroup,
                    ),
                  ),
                if (canDelete)
                  CommandMenuAnchor<_GroupHeaderAction>(
                    title: 'Group actions',
                    enabled: !mutating,
                    options: const [
                      CommandMenuOption(
                        value: _GroupHeaderAction.delete,
                        label: 'Delete group',
                        icon: DIcons.trashCan,
                        key: ValueKey('delete-group'),
                        destructive: true,
                      ),
                    ],
                    onSelected: (_) => unawaited(_deleteGroup(context)),
                    builder: (context, openMenu) => DButton.iconOnly(
                      key: const ValueKey('group-actions'),
                      icon: const DIcon(DIcons.ellipsis, size: 16),
                      tooltip: 'More group actions',
                      size: overflowButtonSize,
                      onPressed: openMenu,
                    ),
                  ),
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GroupFlair(
                      siteUrl: siteUrl,
                      group: group,
                      size: compact ? 46 : 54,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '@${group.name}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 24),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: actions,
                        ),
                      ),
                    ],
                  ],
                ),
                if (group.plainBio case final bio?
                    when bio.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(bio, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (group.isGroupOwner)
                      const _HeaderFact(
                        icon: DIcons.certificate,
                        label: 'Owner',
                      )
                    else if (group.isGroupUser)
                      const _HeaderFact(icon: DIcons.check, label: 'Member'),
                    if (group.isPrivate)
                      const _HeaderFact(icon: DIcons.lock, label: 'Private'),
                  ],
                ),
                if (compact) ...[
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${group.userCount} '
                        '${group.userCount == 1 ? 'member' : 'members'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: actions,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _GroupHeaderAction { delete }

Future<bool?> _confirmDeleteGroup(BuildContext context, Group group) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _DeleteGroupDialog(group: group),
  );
}

class _DeleteGroupDialog extends StatefulWidget {
  const _DeleteGroupDialog({required this.group});

  final Group group;

  @override
  State<_DeleteGroupDialog> createState() => _DeleteGroupDialogState();
}

class _DeleteGroupDialogState extends State<_DeleteGroupDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete group?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This cannot be undone. Type “${widget.group.name}” to confirm.'),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('group-delete-confirmation'),
          controller: controller,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
      ],
    ),
    actions: [
      DButton(
        label: const Text('Cancel'),
        onPressed: () => Navigator.pop(context, false),
      ),
      DButton(
        key: const ValueKey('confirm-delete-group'),
        label: const Text('Delete permanently'),
        variant: DButtonVariant.danger,
        onPressed: controller.text == widget.group.name
            ? () => Navigator.pop(context, true)
            : null,
      ),
    ],
  );
}

class _HeaderFact extends StatelessWidget {
  const _HeaderFact({required this.icon, required this.label});

  final DIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DIcon(icon, size: 13),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _PrimaryTabs extends StatelessWidget {
  const _PrimaryTabs({
    required this.route,
    required this.group,
    required this.data,
    required this.pluginTabs,
    required this.onSelect,
  });

  final GroupRoute route;
  final Group group;
  final GroupPageData data;
  final List<_OwnedPluginTab> pluginTabs;
  final ValueChanged<GroupRoute> onSelect;

  @override
  Widget build(BuildContext context) {
    final tabs = <_GroupTab>[
      _GroupTab(
        section: GroupRoute.members,
        label: 'Members',
        icon: DIcons.users,
        count: group.userCount,
      ),
      const _GroupTab(
        section: GroupRoute.activity,
        label: 'Activity',
        icon: DIcons.fire,
      ),
      if (group.canManage && group.allowMembershipRequests)
        _GroupTab(
          section: GroupRoute.requests,
          label: 'Requests',
          icon: DIcons.userPlus,
          count: data.requesters?.total,
        ),
      if (group.canShowMessages(
        canSendPrivateMessages: data.canSendPrivateMessages,
        isAdmin: data.isAdmin,
      ))
        _GroupTab(
          section: GroupRoute.messages,
          label: 'Messages',
          icon: DIcons.envelope,
          count: group.messageCount,
        ),
      if (group.canManage)
        const _GroupTab(
          section: GroupRoute.manage,
          label: 'Manage',
          icon: DIcons.gear,
        ),
      const _GroupTab(
        section: GroupRoute.permissions,
        label: 'Permissions',
        icon: DIcons.certificate,
      ),
    ];

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              ContentReadingLane.breakpointWidthOf(
                context,
                constraints.maxWidth,
              ) <
              _groupDesktopBreakpoint;
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).shell.divider),
              ),
            ),
            child: ContentReadingLaneBox(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                key: const ValueKey('group-primary-tabs'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    for (final tab in tabs)
                      _TabButton(
                        key: ValueKey('group-tab-${tab.section}'),
                        selected:
                            !route.isPlugin && route.section == tab.section,
                        label: tab.label,
                        icon: tab.icon,
                        count: tab.count,
                        compact: compact,
                        onTap: () => onSelect(
                          GroupRoute.detail(
                            group.name,
                            section: tab.section,
                            subsection: _defaultSubsection(
                              tab.section,
                              group,
                              data,
                            ),
                          ),
                        ),
                      ),
                    for (final owned in pluginTabs)
                      _TabButton(
                        key: ValueKey('group-plugin-tab-${owned.tab.section}'),
                        selected:
                            route.isPlugin &&
                            route.pluginOwner == owned.owner &&
                            route.section == owned.tab.section,
                        label: owned.tab.label,
                        icon: owned.tab.icon,
                        count: owned.tab.count,
                        compact: compact,
                        onTap: () => onSelect(
                          GroupRoute.plugin(
                            groupName: group.name,
                            owner: owned.owner,
                            section: owned.tab.section,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String? _defaultSubsection(String section, Group group, GroupPageData data) =>
    switch (section) {
      GroupRoute.activity =>
        group.canSeeMembers
            ? GroupRoute.posts
            : data.mentionsEnabled
            ? GroupRoute.mentions
            : null,
      GroupRoute.messages => GroupRoute.inbox,
      GroupRoute.manage => GroupRoute.profile,
      _ => null,
    };

@immutable
final class _GroupTab {
  const _GroupTab({
    required this.section,
    required this.label,
    required this.icon,
    this.count,
  });

  final String section;
  final String label;
  final DIconData icon;
  final int? count;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.compact,
    this.count,
  });

  final bool selected;
  final String label;
  final DIconData icon;
  final int? count;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Material(
      color: selected ? Theme.of(context).shell.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              if (!compact) ...[
                DIcon(icon, size: 14),
                const SizedBox(width: 7),
              ],
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (!compact && count != null) ...[
                const SizedBox(width: 6),
                Text('$count', style: Theme.of(context).textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
