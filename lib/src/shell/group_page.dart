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
import 'choice_menu.dart';
import 'command_menu.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

enum GroupMembershipAction { join, leave, request }

enum GroupRequestAction { accept, deny }

enum GroupMemberAction {
  remove,
  makeOwner,
  removeOwner,
  makePrimary,
  removePrimary,
}

typedef GroupMemberSortChanged = void Function(String order, bool ascending);
typedef GroupAddMembers =
    Future<GroupMembershipMutationResult?> Function(
      List<String> usernames,
      List<String> emails,
    );
typedef GroupCreateInvite =
    Future<GroupInvite?> Function({String? email, String? customMessage});
typedef GroupMemberActionCallback =
    Future<bool> Function(GroupMember member, GroupMemberAction action);

@immutable
final class GroupManageUpdate {
  const GroupManageUpdate({required this.subsection, required this.values});

  final String subsection;
  final Map<String, Object?> values;
}

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
    this.saving = false,
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
  final bool saving;
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
    this.onLoadRequested,
    this.onRefresh,
    this.onLoadMore,
    this.onSelectRoute,
    this.onMembershipAction,
    this.onMessageGroup,
    this.onSwitchGroup,
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
  final ValueChanged<GroupRoute>? onLoadRequested;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final ValueChanged<GroupRoute>? onSelectRoute;
  final Future<void> Function(GroupMembershipAction action)? onMembershipAction;
  final VoidCallback? onMessageGroup;
  final ValueChanged<String>? onSwitchGroup;
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
  final Future<void> Function(GroupManageUpdate update)? onSaveManage;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  GroupRoute? _requestedRoute;
  bool _requestScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(GroupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.route != widget.route) {
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    if (_requestScheduled || _requestedRoute == widget.route) return;
    _requestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestScheduled = false;
      if (!mounted || _requestedRoute == widget.route) return;
      _requestedRoute = widget.route;
      widget.onLoadRequested?.call(widget.route);
    });
  }

  void _select(GroupRoute route) {
    if (widget.onSelectRoute case final callback?) {
      callback(route);
      return;
    }
    final shell = ShellScope.maybeRead(context);
    final username = shell?.currentInstance?.user?.username;
    shell?.selectGroupRoute(route, feedPath: route.topicFeedPath(username));
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
        if (widget.data.loading) const LinearProgressIndicator(minHeight: 2),
        _GroupHeader(
          siteUrl: widget.siteUrl,
          detail: detail,
          group: group,
          isAdmin: widget.data.isAdmin,
          mutating: widget.data.mutating,
          onMembershipAction: widget.onMembershipAction,
          onMessageGroup: widget.onMessageGroup,
          onSwitchGroup: widget.onSwitchGroup,
          onDeleteGroup: widget.onDeleteGroup,
          onSelectRoute: _select,
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

enum _GroupHeaderCommand { settings, copyLink, delete }

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.siteUrl,
    required this.detail,
    required this.group,
    required this.isAdmin,
    required this.mutating,
    required this.onMembershipAction,
    required this.onMessageGroup,
    required this.onSwitchGroup,
    required this.onDeleteGroup,
    required this.onSelectRoute,
  });

  final String siteUrl;
  final GroupDetail detail;
  final Group group;
  final bool isAdmin;
  final bool mutating;
  final Future<void> Function(GroupMembershipAction action)? onMembershipAction;
  final VoidCallback? onMessageGroup;
  final ValueChanged<String>? onSwitchGroup;
  final Future<bool> Function()? onDeleteGroup;
  final ValueChanged<GroupRoute> onSelectRoute;

  List<CommandMenuOption<_GroupHeaderCommand>> get commands => [
    if (group.canManage)
      const CommandMenuOption(
        value: _GroupHeaderCommand.settings,
        label: 'Group settings',
        icon: DIcons.gear,
      ),
    const CommandMenuOption(
      value: _GroupHeaderCommand.copyLink,
      label: 'Copy group link',
      icon: DIcons.link,
    ),
    if (isAdmin && !group.automatic && onDeleteGroup != null)
      const CommandMenuOption(
        value: _GroupHeaderCommand.delete,
        label: 'Delete group',
        icon: DIcons.trashCan,
        dividerBefore: true,
        destructive: true,
      ),
  ];

  Future<void> _handleCommand(
    BuildContext context,
    _GroupHeaderCommand command,
  ) async {
    switch (command) {
      case _GroupHeaderCommand.settings:
        onSelectRoute(
          GroupRoute.detail(
            group.name,
            section: GroupRoute.manage,
            subsection: GroupRoute.profile,
          ),
        );
        break;
      case _GroupHeaderCommand.copyLink:
        final link = _resolveSitePath(
          siteUrl,
          'g/${Uri.encodeComponent(group.name)}',
        );
        await Clipboard.setData(ClipboardData(text: link));
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Group link copied.')));
        }
        break;
      case _GroupHeaderCommand.delete:
        if (await _confirmDeleteGroup(context, group) != true) return;
        final deleted = await onDeleteGroup?.call() ?? false;
        if (context.mounted && !deleted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('The group could not be deleted.')),
          );
        }
        break;
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
      GroupMembershipAction.join => 'Join',
      GroupMembershipAction.leave => 'Leave',
      GroupMembershipAction.request => 'Request to join',
      null => null,
    };

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GroupAvatar(group: group, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: InkWell(
                          key: const ValueKey('group-switcher'),
                          borderRadius: BorderRadius.circular(6),
                          onTap:
                              detail.visibleGroupNames.length > 1 &&
                                  onSwitchGroup != null
                              ? () => _showGroupSwitcher(
                                  context,
                                  current: group.name,
                                  names: detail.visibleGroupNames,
                                  onSelected: onSwitchGroup!,
                                )
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group.label,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        '@${group.name}',
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (detail.visibleGroupNames.length > 1) ...[
                                  const SizedBox(width: 6),
                                  const DIcon(DIcons.chevronDown, size: 13),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
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
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (actionLabel != null)
                        DButton(
                          key: ValueKey('group-${membershipAction!.name}'),
                          label: Text(actionLabel),
                          icon: membershipAction == GroupMembershipAction.leave
                              ? const DIcon(DIcons.xmark, size: 16)
                              : const DIcon(DIcons.userPlus, size: 16),
                          loading: mutating,
                          variant:
                              membershipAction == GroupMembershipAction.leave
                              ? DButtonVariant.standard
                              : DButtonVariant.primary,
                          onPressed: onMembershipAction == null
                              ? null
                              : () => unawaited(
                                  onMembershipAction!(membershipAction),
                                ),
                        ),
                      if (group.messageable && onMessageGroup != null)
                        DButton(
                          key: const ValueKey('group-message'),
                          icon: const DIcon(DIcons.envelope, size: 16),
                          label: Text(
                            constraints.maxWidth < 360 ? 'Message' : 'Message',
                          ),
                          onPressed: onMessageGroup,
                        ),
                      CommandMenuAnchor<_GroupHeaderCommand>(
                        title: 'Group actions',
                        options: commands,
                        onSelected: (command) =>
                            unawaited(_handleCommand(context, command)),
                        builder: (context, openMenu) => DButton(
                          key: const ValueKey('group-more-actions'),
                          icon: const DIcon(DIcons.ellipsisVertical, size: 16),
                          label: const Text('More'),
                          onPressed: openMenu,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool?> _confirmDeleteGroup(BuildContext context, Group group) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _DeleteGroupDialog(group: group),
  );
}

String _resolveSitePath(String siteUrl, String path) {
  final base = Uri.parse(siteUrl.endsWith('/') ? siteUrl : '$siteUrl/');
  return base.resolve(path).toString();
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

Future<void> _showGroupSwitcher(
  BuildContext context, {
  required String current,
  required List<String> names,
  required ValueChanged<String> onSelected,
}) async {
  final selected = await showShellSheet<String>(
    context: context,
    title: 'Switch group',
    dialogOnDesktop: true,
    padding: EdgeInsets.zero,
    builder: (_) => _GroupSwitcher(current: current, names: names),
  );
  if (selected != null) onSelected(selected);
}

class _GroupSwitcher extends StatefulWidget {
  const _GroupSwitcher({required this.current, required this.names});

  final String current;
  final List<String> names;

  @override
  State<_GroupSwitcher> createState() => _GroupSwitcherState();
}

class _GroupSwitcherState extends State<_GroupSwitcher> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final names = widget.names
        .where((name) => name.toLowerCase().contains(normalized))
        .toList(growable: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            key: const ValueKey('group-switcher-search'),
            autofocus: true,
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Find a group',
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: names.length,
            itemBuilder: (context, index) {
              final name = names[index];
              return ListTile(
                key: ValueKey('switch-group-$name'),
                leading: CircleAvatar(
                  child: Text(
                    name.characters.firstOrNull?.toUpperCase() ?? 'G',
                  ),
                ),
                title: Text(name),
                trailing: name == widget.current
                    ? const DIcon(DIcons.check, size: 15)
                    : null,
                onTap: name == widget.current
                    ? null
                    : () => Navigator.pop(context, name),
              );
            },
          ),
        ),
      ],
    );
  }
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

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.group, required this.size});

  final Group group;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Theme.of(context).colorScheme.primaryContainer,
    ),
    child: Text(
      group.label.characters.firstOrNull?.toUpperCase() ?? 'G',
      style: TextStyle(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        fontSize: size * .42,
        fontWeight: FontWeight.w700,
      ),
    ),
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
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).shell.divider),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final tab in tabs)
                _TabButton(
                  key: ValueKey('group-tab-${tab.section}'),
                  selected: !route.isPlugin && route.section == tab.section,
                  label: tab.label,
                  icon: tab.icon,
                  count: tab.count,
                  onTap: () => onSelect(
                    GroupRoute.detail(
                      group.name,
                      section: tab.section,
                      subsection: _defaultSubsection(tab.section, group, data),
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
    this.count,
  });

  final bool selected;
  final String label;
  final DIconData icon;
  final int? count;
  final VoidCallback onTap;

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
              DIcon(icon, size: 14),
              const SizedBox(width: 7),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (count case final count?) ...[
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

class _MembersSection extends StatefulWidget {
  const _MembersSection({
    required this.siteUrl,
    required this.page,
    required this.group,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.onOpenMember,
    required this.onLoadMore,
    required this.filter,
    required this.order,
    required this.ascending,
    required this.currentUserStaff,
    required this.mutating,
    required this.canInviteToForum,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onSearchUsers,
    required this.onAddMembers,
    required this.onCreateInvite,
    required this.onMemberAction,
  });

  final String siteUrl;
  final GroupMembersPage? page;
  final Group group;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final void Function(BuildContext context, GroupMember member) onOpenMember;
  final VoidCallback? onLoadMore;
  final String filter;
  final String order;
  final bool ascending;
  final bool currentUserStaff;
  final bool mutating;
  final bool canInviteToForum;
  final ValueChanged<String>? onFilterChanged;
  final GroupMemberSortChanged? onSortChanged;
  final Future<List<FoundUser>> Function(String query)? onSearchUsers;
  final GroupAddMembers? onAddMembers;
  final GroupCreateInvite? onCreateInvite;
  final GroupMemberActionCallback? onMemberAction;

  @override
  State<_MembersSection> createState() => _MembersSectionState();
}

class _MembersSectionState extends State<_MembersSection> {
  late final TextEditingController searchController = TextEditingController(
    text: widget.filter,
  );
  Timer? debounce;

  @override
  void didUpdateWidget(_MembersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter &&
        searchController.text != widget.filter) {
      searchController.text = widget.filter;
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _search(String value) {
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 300),
      () => widget.onFilterChanged?.call(value.trim()),
    );
  }

  Future<void> _addMembers() async {
    if (widget.onAddMembers == null || widget.onSearchUsers == null) return;
    await showShellSheet<void>(
      context: context,
      title: 'Add members',
      dialogOnDesktop: true,
      desktopDialogConstraints: const BoxConstraints(
        maxWidth: 560,
        maxHeight: 640,
      ),
      builder: (_) => _AddGroupMembersSheet(
        searchUsers: widget.onSearchUsers!,
        onAdd: widget.onAddMembers!,
      ),
    );
  }

  Future<void> _inviteMembers() => showShellSheet<void>(
    context: context,
    title: 'Invite to group',
    dialogOnDesktop: true,
    builder: (_) => _InviteGroupSheet(
      siteUrl: widget.siteUrl,
      onCreate: widget.onCreateInvite!,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.group.canSeeMembers) {
      return const _GroupState(
        icon: DIcons.lock,
        title: 'This group’s members are private.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MembersToolbar(
          total: widget.page?.total ?? widget.group.userCount ?? 0,
          controller: searchController,
          order: widget.order,
          ascending: widget.ascending,
          canManage: widget.group.canManage,
          canInvite: widget.canInviteToForum,
          mutating: widget.mutating,
          onSearch: _search,
          onSortChanged: widget.onSortChanged,
          onAddMembers: widget.onAddMembers == null ? null : _addMembers,
          onInviteMembers: widget.onCreateInvite == null
              ? null
              : _inviteMembers,
        ),
        Expanded(child: _membersBody()),
      ],
    );
  }

  Widget _membersBody() {
    final page = widget.page;
    if (page == null) {
      if (widget.error != null) {
        return _GroupState(
          icon: DIcons.triangleExclamation,
          title: widget.error!,
        );
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (page.members.isEmpty && !widget.loading) {
      return _GroupState(
        icon: widget.filter.isEmpty ? DIcons.users : DIcons.magnifyingGlass,
        title: widget.filter.isEmpty
            ? 'This group has no members.'
            : 'No members match “${widget.filter}”.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 760;
        final extra = widget.hasMore || widget.loadingMore ? 1 : 0;
        return ListView.separated(
          key: const PageStorageKey('group-members-scroll'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          itemCount: page.members.length + extra + (desktop ? 1 : 0),
          separatorBuilder: (_, _) => desktop
              ? Divider(height: 1, color: Theme.of(context).shell.divider)
              : const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (desktop && index == 0) return const _MemberTableHeader();
            final memberIndex = desktop ? index - 1 : index;
            if (memberIndex == page.members.length) {
              return _LoadMoreRow(
                loading: widget.loadingMore,
                onPressed: widget.onLoadMore,
              );
            }
            final member = page.members[memberIndex];
            final actions = _MemberActions(
              member: member,
              group: widget.group,
              currentUserStaff: widget.currentUserStaff,
              mutating: widget.mutating,
              onAction: widget.onMemberAction,
            );
            return desktop
                ? _MemberTableRow(
                    member: member,
                    onTap: () => widget.onOpenMember(context, member),
                    actions: actions,
                  )
                : _MemberCard(
                    member: member,
                    onTap: () => widget.onOpenMember(context, member),
                    actions: actions,
                  );
          },
        );
      },
    );
  }
}

class _MembersToolbar extends StatelessWidget {
  const _MembersToolbar({
    required this.total,
    required this.controller,
    required this.order,
    required this.ascending,
    required this.canManage,
    required this.canInvite,
    required this.mutating,
    required this.onSearch,
    required this.onSortChanged,
    required this.onAddMembers,
    required this.onInviteMembers,
  });

  final int total;
  final TextEditingController controller;
  final String order;
  final bool ascending;
  final bool canManage;
  final bool canInvite;
  final bool mutating;
  final ValueChanged<String> onSearch;
  final GroupMemberSortChanged? onSortChanged;
  final VoidCallback? onAddMembers;
  final VoidCallback? onInviteMembers;

  static const options = [
    ChoiceMenuOption(
      value: 'username_lower',
      title: 'Username',
      description: 'Alphabetical member order',
    ),
    ChoiceMenuOption(
      value: 'added_at',
      title: 'Date added',
      description: 'When members joined the group',
    ),
    ChoiceMenuOption(
      value: 'last_posted_at',
      title: 'Last post',
      description: 'Most recently posted members',
    ),
    ChoiceMenuOption(
      value: 'last_seen_at',
      title: 'Last active',
      description: 'Most recently seen members',
    ),
  ];

  String get sortLabel => options
      .firstWhere((option) => option.value == order, orElse: () => options.last)
      .title;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Members ($total)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (canManage)
                  DButton(
                    key: const ValueKey('add-group-members'),
                    size: DButtonSize.small,
                    icon: const DIcon(DIcons.userPlus, size: 14),
                    label: const Text('Add members'),
                    loading: mutating,
                    onPressed: onAddMembers,
                  ),
                if (canInvite)
                  DButton(
                    key: const ValueKey('invite-group-members'),
                    size: DButtonSize.small,
                    icon: const DIcon(DIcons.paperPlane, size: 14),
                    label: const Text('Invite'),
                    onPressed: onInviteMembers,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final search = TextField(
                  key: const ValueKey('group-member-search'),
                  controller: controller,
                  onChanged: onSearch,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search members',
                    isDense: true,
                  ),
                );
                final sorting = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChoiceMenuAnchor<String>(
                      title: 'Sort members',
                      value: order,
                      options: options,
                      onSelected: (value) =>
                          onSortChanged?.call(value, value == 'username_lower'),
                      enabled: onSortChanged != null,
                      builder: (context, openMenu) => DButton(
                        key: const ValueKey('group-member-sort'),
                        size: DButtonSize.small,
                        icon: const DIcon(DIcons.chevronDown, size: 13),
                        label: Text(sortLabel),
                        onPressed: openMenu,
                      ),
                    ),
                    const SizedBox(width: 6),
                    DButton.iconOnly(
                      key: const ValueKey('group-member-sort-direction'),
                      size: DButtonSize.small,
                      icon: Transform.rotate(
                        angle: ascending ? 0 : 3.141592653589793,
                        child: const DIcon(DIcons.arrowUp, size: 14),
                      ),
                      tooltip: ascending ? 'Ascending' : 'Descending',
                      onPressed: onSortChanged == null
                          ? null
                          : () => onSortChanged!(order, !ascending),
                    ),
                  ],
                );
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: sorting),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 10),
                    sorting,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _MemberTableHeader extends StatelessWidget {
  const _MemberTableHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        Expanded(flex: 5, child: Text('Member')),
        Expanded(flex: 2, child: Text('Added')),
        Expanded(flex: 2, child: Text('Last post')),
        Expanded(flex: 2, child: Text('Last seen')),
        SizedBox(width: 48),
      ],
    ),
  );
}

class _MemberTableRow extends StatelessWidget {
  const _MemberTableRow({
    required this.member,
    required this.onTap,
    required this.actions,
  });

  final GroupMember member;
  final VoidCallback onTap;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(flex: 5, child: _MemberIdentity(member: member)),
            Expanded(flex: 2, child: _MemberDate(value: member.addedAt)),
            Expanded(
              flex: 2,
              child: _MemberRelativeDate(value: member.lastPostedAt),
            ),
            Expanded(
              flex: 2,
              child: _MemberRelativeDate(value: member.lastSeenAt),
            ),
            SizedBox(width: 48, child: actions),
          ],
        ),
      ),
    ),
  );
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onTap,
    required this.actions,
  });

  final GroupMember member;
  final VoidCallback onTap;
  final Widget actions;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: _MemberIdentity(member: member, mobile: true)),
                actions,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MemberIdentity extends StatelessWidget {
  const _MemberIdentity({required this.member, this.mobile = false});

  final GroupMember member;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ClipOval(
          child: AvatarImage(
            url: member.avatarUrl,
            size: 42,
            fallback: CircleAvatar(
              radius: 21,
              child: Text(
                member.username.characters.firstOrNull?.toUpperCase() ?? '?',
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    member.name?.trim().isNotEmpty == true
                        ? member.name!
                        : member.username,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (member.owner)
                    const _MemberBadge(label: 'Owner')
                  else if (member.primary)
                    const _MemberBadge(label: 'Primary'),
                ],
              ),
              Text(
                '@${member.username}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (member.title case final title?)
                Text(title, style: theme.textTheme.bodySmall),
              if (mobile) ...[
                const SizedBox(height: 7),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _MobileMemberFact(label: 'Added', value: member.addedAt),
                    _MobileMemberFact(
                      label: 'Posted',
                      value: member.lastPostedAt,
                      relative: true,
                    ),
                    _MobileMemberFact(
                      label: 'Seen',
                      value: member.lastSeenAt,
                      relative: true,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberBadge extends StatelessWidget {
  const _MemberBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _MobileMemberFact extends StatelessWidget {
  const _MobileMemberFact({
    required this.label,
    required this.value,
    this.relative = false,
  });

  final String label;
  final DateTime? value;
  final bool relative;

  @override
  Widget build(BuildContext context) => Text(
    '$label: ${value == null
        ? '—'
        : relative
        ? relativeTime(value!)
        : _dateText(context, value!)}',
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _MemberDate extends StatelessWidget {
  const _MemberDate({required this.value});

  final DateTime? value;

  @override
  Widget build(BuildContext context) => Text(
    value == null ? '—' : _dateText(context, value!),
    style: Theme.of(context).textTheme.bodySmall,
  );
}

class _MemberRelativeDate extends StatelessWidget {
  const _MemberRelativeDate({required this.value});

  final DateTime? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const Text('—');
    return Tooltip(
      message: _dateTimeText(context, value!),
      child: Text(
        relativeTime(value!),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

String _dateText(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatMediumDate(value.toLocal());

String _dateTimeText(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatMediumDate(local)} ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

class _MemberActions extends StatelessWidget {
  const _MemberActions({
    required this.member,
    required this.group,
    required this.currentUserStaff,
    required this.mutating,
    required this.onAction,
  });

  final GroupMember member;
  final Group group;
  final bool currentUserStaff;
  final bool mutating;
  final GroupMemberActionCallback? onAction;

  List<CommandMenuOption<GroupMemberAction>> get options => [
    if (group.canAdminGroup || (group.canEditGroup && !member.owner))
      CommandMenuOption(
        value: member.owner
            ? GroupMemberAction.removeOwner
            : GroupMemberAction.makeOwner,
        label: member.owner ? 'Remove as owner' : 'Make owner',
        icon: DIcons.certificate,
      ),
    if (currentUserStaff)
      CommandMenuOption(
        value: member.primary
            ? GroupMemberAction.removePrimary
            : GroupMemberAction.makePrimary,
        label: member.primary
            ? 'Remove as primary group'
            : 'Make primary group',
        icon: DIcons.star,
      ),
    if (group.canManage)
      const CommandMenuOption(
        value: GroupMemberAction.remove,
        label: 'Remove from group',
        icon: DIcons.trashCan,
        dividerBefore: true,
        destructive: true,
      ),
  ];

  Future<void> _run(BuildContext context, GroupMemberAction action) async {
    if (action == GroupMemberAction.remove) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove @${member.username}?'),
          content: Text(
            'This member will lose access granted by ${group.label}.',
          ),
          actions: [
            DButton(
              label: const Text('Cancel'),
              onPressed: () => Navigator.pop(context, false),
            ),
            DButton(
              label: const Text('Remove member'),
              variant: DButtonVariant.danger,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final saved = await onAction?.call(member, action) ?? false;
    if (context.mounted && !saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The member could not be updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty || onAction == null) return const SizedBox.shrink();
    return CommandMenuAnchor<GroupMemberAction>(
      title: 'Manage @${member.username}',
      options: options,
      enabled: !mutating,
      onSelected: (action) => unawaited(_run(context, action)),
      builder: (context, openMenu) => DButton.iconOnly(
        key: ValueKey('manage-member-${member.username}'),
        size: DButtonSize.small,
        icon: const DIcon(DIcons.wrench, size: 14),
        tooltip: 'Manage @${member.username}',
        onPressed: openMenu,
      ),
    );
  }
}

class _AddGroupMembersSheet extends StatefulWidget {
  const _AddGroupMembersSheet({required this.searchUsers, required this.onAdd});

  final Future<List<FoundUser>> Function(String query) searchUsers;
  final GroupAddMembers onAdd;

  @override
  State<_AddGroupMembersSheet> createState() => _AddGroupMembersSheetState();
}

class _AddGroupMembersSheetState extends State<_AddGroupMembersSheet> {
  final selectedUsernames = <String>{};
  final selectedEmails = <String>{};
  List<FoundUser> results = const [];
  String query = '';
  String? error;
  Timer? debounce;
  int sequence = 0;
  bool searching = false;
  bool saving = false;

  bool get queryIsEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(query.trim());

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  void _search(String value) {
    setState(() {
      query = value;
      error = null;
    });
    debounce?.cancel();
    final request = ++sequence;
    if (value.trim().length < 2) {
      setState(() {
        results = const [];
        searching = false;
      });
      return;
    }
    debounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => searching = true);
      final found = await widget.searchUsers(value.trim());
      if (!mounted || request != sequence) return;
      setState(() {
        results = found;
        searching = false;
      });
    });
  }

  Future<void> _save() async {
    if (saving || (selectedUsernames.isEmpty && selectedEmails.isEmpty)) return;
    setState(() {
      saving = true;
      error = null;
    });
    final result = await widget.onAdd(
      selectedUsernames.toList(growable: false),
      selectedEmails.toList(growable: false),
    );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        saving = false;
        error = 'The selected members could not be added.';
      });
      return;
    }
    if (result.skippedUsernames.isNotEmpty) {
      setState(() {
        saving = false;
        error = 'Not added: ${result.skippedUsernames.join(', ')}';
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final email = query.trim().toLowerCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('add-members-search'),
          autofocus: true,
          onChanged: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Username or email address',
          ),
        ),
        if (searching) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 10),
        if (queryIsEmail)
          CheckboxListTile(
            key: ValueKey('add-email-$email'),
            contentPadding: EdgeInsets.zero,
            value: selectedEmails.contains(email),
            title: Text(email),
            subtitle: const Text('Add by email address'),
            onChanged: (selected) => setState(() {
              selected == true
                  ? selectedEmails.add(email)
                  : selectedEmails.remove(email);
            }),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (context, index) {
              final user = results[index];
              return CheckboxListTile(
                key: ValueKey('add-user-${user.username}'),
                contentPadding: EdgeInsets.zero,
                value: selectedUsernames.contains(user.username),
                secondary: ClipOval(
                  child: AvatarImage(
                    url: user.avatarUrl,
                    size: 36,
                    fallback: CircleAvatar(
                      radius: 18,
                      child: Text(
                        user.username.characters.firstOrNull?.toUpperCase() ??
                            '?',
                      ),
                    ),
                  ),
                ),
                title: Text(user.name ?? user.username),
                subtitle: Text('@${user.username}'),
                onChanged: (selected) => setState(() {
                  selected == true
                      ? selectedUsernames.add(user.username)
                      : selectedUsernames.remove(user.username);
                }),
              );
            },
          ),
        ),
        if (error case final error?) ...[
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 14),
        DButton(
          key: const ValueKey('submit-add-members'),
          label: Text(
            selectedUsernames.length + selectedEmails.length == 1
                ? 'Add member'
                : 'Add members',
          ),
          variant: DButtonVariant.primary,
          loading: saving,
          onPressed: selectedUsernames.isEmpty && selectedEmails.isEmpty
              ? null
              : _save,
        ),
      ],
    );
  }
}

class _InviteGroupSheet extends StatefulWidget {
  const _InviteGroupSheet({required this.siteUrl, required this.onCreate});

  final String siteUrl;
  final GroupCreateInvite onCreate;

  @override
  State<_InviteGroupSheet> createState() => _InviteGroupSheetState();
}

class _InviteGroupSheetState extends State<_InviteGroupSheet> {
  final email = TextEditingController();
  final message = TextEditingController();
  bool saving = false;
  String? error;
  String? link;

  @override
  void dispose() {
    email.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      saving = true;
      error = null;
    });
    final normalizedEmail = email.text.trim();
    final invite = await widget.onCreate(
      email: normalizedEmail.isEmpty ? null : normalizedEmail,
      customMessage: message.text.trim().isEmpty ? null : message.text.trim(),
    );
    if (!mounted) return;
    if (invite == null) {
      setState(() {
        saving = false;
        error = 'The invitation could not be created.';
      });
      return;
    }
    if (normalizedEmail.isNotEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invitation sent to $normalizedEmail.')),
      );
      return;
    }
    final rawLink = invite.link;
    setState(() {
      saving = false;
      link = rawLink == null ? null : _resolveSitePath(widget.siteUrl, rawLink);
      error = rawLink == null
          ? 'The server did not return an invite link.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Enter an email to send an invitation, or leave it blank to create a one-use link.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('group-invite-email'),
        controller: email,
        keyboardType: TextInputType.emailAddress,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Email (optional)'),
      ),
      if (email.text.trim().isNotEmpty) ...[
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('group-invite-message'),
          controller: message,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Message (optional)'),
        ),
      ],
      if (link case final link?) ...[
        const SizedBox(height: 12),
        SelectableText(link),
        const SizedBox(height: 8),
        DButton(
          key: const ValueKey('copy-group-invite'),
          icon: const DIcon(DIcons.copy, size: 15),
          label: const Text('Copy invite link'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite link copied.')),
              );
            }
          },
        ),
      ],
      if (error case final error?) ...[
        const SizedBox(height: 8),
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (link == null) ...[
        const SizedBox(height: 14),
        DButton(
          key: const ValueKey('create-group-invite'),
          icon: const DIcon(DIcons.paperPlane, size: 15),
          label: Text(
            email.text.trim().isEmpty ? 'Create link' : 'Send invite',
          ),
          variant: DButtonVariant.primary,
          loading: saving,
          onPressed: _create,
        ),
      ],
    ],
  );
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.route,
    required this.group,
    required this.page,
    required this.topicFeed,
    required this.mentionsEnabled,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.onSelect,
    required this.onOpenPost,
    required this.onLoadMore,
  });

  final GroupRoute route;
  final Group group;
  final GroupActivityPage? page;
  final Widget? topicFeed;
  final bool mentionsEnabled;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final ValueChanged<GroupRoute> onSelect;
  final ValueChanged<GroupActivityPost>? onOpenPost;
  final VoidCallback? onLoadMore;

  String get selected =>
      route.subsection ??
      (group.canSeeMembers ? GroupRoute.posts : GroupRoute.mentions);

  @override
  Widget build(BuildContext context) {
    final options = <_Subtab>[
      if (group.canSeeMembers) const _Subtab(GroupRoute.posts, 'Posts'),
      if (group.canSeeMembers) const _Subtab(GroupRoute.topics, 'Topics'),
      if (mentionsEnabled) const _Subtab(GroupRoute.mentions, 'Mentions'),
    ];
    return Column(
      children: [
        _Subtabs(
          selected: selected,
          options: options,
          onSelect: (subsection) => onSelect(
            GroupRoute.detail(
              group.name,
              section: GroupRoute.activity,
              subsection: subsection,
            ),
          ),
        ),
        Expanded(
          child: selected == GroupRoute.topics
              ? topicFeed ??
                    const _GroupState(
                      icon: DIcons.list,
                      title: 'Topics are not available yet.',
                    )
              : _ActivityRows(
                  page: page,
                  kind: selected == GroupRoute.mentions ? 'mentions' : 'posts',
                  loading: loading,
                  loadingMore: loadingMore,
                  hasMore: hasMore,
                  error: error,
                  onOpenPost: onOpenPost,
                  onLoadMore: onLoadMore,
                ),
        ),
      ],
    );
  }
}

class _ActivityRows extends StatelessWidget {
  const _ActivityRows({
    required this.page,
    required this.kind,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.onOpenPost,
    required this.onLoadMore,
  });

  final GroupActivityPage? page;
  final String kind;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final ValueChanged<GroupActivityPost>? onOpenPost;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (page == null) {
      if (error != null) {
        return _GroupState(icon: DIcons.triangleExclamation, title: error!);
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (page!.posts.isEmpty && !loading) {
      return _GroupState(icon: DIcons.comment, title: 'No $kind yet.');
    }
    return ListView.separated(
      key: PageStorageKey('group-activity-$kind-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: page!.posts.length + (hasMore || loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == page!.posts.length) {
          return _LoadMoreRow(loading: loadingMore, onPressed: onLoadMore);
        }
        final post = page!.posts[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                onTap: () => onOpenPost?.call(post),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.topicTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        post.plainExcerpt,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          if (post.username case final username?)
                            Expanded(
                              child: Text(
                                '@$username',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          else
                            const Spacer(),
                          Text(
                            '#${post.postNumber}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 5),
                          const DIcon(DIcons.chevronRight, size: 13),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RequestsSection extends StatelessWidget {
  const _RequestsSection({
    required this.page,
    required this.loading,
    required this.mutating,
    required this.error,
    required this.onAction,
    required this.onLoadMore,
    required this.hasMore,
  });

  final GroupRequestersPage? page;
  final bool loading;
  final bool mutating;
  final String? error;
  final Future<void> Function(GroupRequester, GroupRequestAction)? onAction;
  final VoidCallback? onLoadMore;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (page == null) {
      if (error != null) {
        return _GroupState(icon: DIcons.triangleExclamation, title: error!);
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (page!.requesters.isEmpty && !loading) {
      return const _GroupState(
        icon: DIcons.userPlus,
        title: 'There are no pending membership requests.',
      );
    }
    return ListView.separated(
      key: const PageStorageKey('group-requests-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: page!.requesters.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == page!.requesters.length) {
          return _LoadMoreRow(loading: loading, onPressed: onLoadMore);
        }
        final requester = page!.requesters[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requester.name?.trim().isNotEmpty == true
                          ? requester.name!
                          : requester.username,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('@${requester.username}'),
                    if (requester.reason case final reason?
                        when reason.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(reason),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        DButton(
                          key: ValueKey('accept-${requester.username}'),
                          label: const Text('Accept'),
                          variant: DButtonVariant.success,
                          size: DButtonSize.small,
                          onPressed: mutating || onAction == null
                              ? null
                              : () => unawaited(
                                  onAction!(
                                    requester,
                                    GroupRequestAction.accept,
                                  ),
                                ),
                        ),
                        DButton(
                          key: ValueKey('deny-${requester.username}'),
                          label: const Text('Deny'),
                          variant: DButtonVariant.danger,
                          size: DButtonSize.small,
                          onPressed: mutating || onAction == null
                              ? null
                              : () => unawaited(
                                  onAction!(requester, GroupRequestAction.deny),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessagesSection extends StatelessWidget {
  const _MessagesSection({
    required this.route,
    required this.group,
    required this.content,
    required this.onSelect,
  });

  final GroupRoute route;
  final Group group;
  final Widget? content;
  final ValueChanged<GroupRoute> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = route.subsection ?? GroupRoute.inbox;
    return Column(
      children: [
        _Subtabs(
          selected: selected,
          options: const [
            _Subtab(GroupRoute.inbox, 'Inbox'),
            _Subtab(GroupRoute.archive, 'Archive'),
          ],
          onSelect: (subsection) => onSelect(
            GroupRoute.detail(
              group.name,
              section: GroupRoute.messages,
              subsection: subsection,
            ),
          ),
        ),
        Expanded(
          child:
              content ??
              const _GroupState(
                icon: DIcons.envelope,
                title: 'Messages are not available yet.',
              ),
        ),
      ],
    );
  }
}

class _PermissionsSection extends StatelessWidget {
  const _PermissionsSection({
    required this.permissions,
    required this.loading,
    required this.error,
  });

  final List<GroupPermission> permissions;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (permissions.isEmpty && loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (permissions.isEmpty && error != null) {
      return _GroupState(icon: DIcons.triangleExclamation, title: error!);
    }
    if (permissions.isEmpty) {
      return const _GroupState(
        icon: DIcons.certificate,
        title: 'This group has no category permissions.',
      );
    }
    return ListView.separated(
      key: const PageStorageKey('group-permissions-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: permissions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final permission = permissions[index];
        final label = switch (permission.type) {
          GroupPermissionType.full => 'Create, reply, and see',
          GroupPermissionType.createPost => 'Reply and see',
          GroupPermissionType.readOnly => 'See',
          GroupPermissionType.unknown => 'Custom access',
        };
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListTile(
              tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              leading: const DIcon(DIcons.lock, size: 17),
              title: Text(permission.category.name),
              subtitle: Text(label),
            ),
          ),
        );
      },
    );
  }
}

@immutable
final class _Subtab {
  const _Subtab(this.value, this.label);

  final String value;
  final String label;
}

class _Subtabs extends StatelessWidget {
  const _Subtabs({
    required this.selected,
    required this.options,
    required this.onSelect,
  });

  final String selected;
  final List<_Subtab> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('group-subtab-${option.value}'),
                label: Text(option.label),
                selected: selected == option.value,
                onSelected: (_) => onSelect(option.value),
              ),
            ),
        ],
      ),
    ),
  );
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: DButton(
        key: const ValueKey('group-load-more'),
        label: const Text('Load more'),
        loading: loading,
        onPressed: onPressed,
      ),
    ),
  );
}

class _ManageSection extends StatelessWidget {
  const _ManageSection({
    super.key,
    required this.route,
    required this.group,
    required this.data,
    required this.onSelect,
    required this.onSave,
    required this.onLoadMore,
  });

  final GroupRoute route;
  final Group group;
  final GroupPageData data;
  final ValueChanged<GroupRoute> onSelect;
  final Future<void> Function(GroupManageUpdate)? onSave;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!group.canManage) {
      return const _GroupState(
        icon: DIcons.lock,
        title: 'You cannot manage this group.',
      );
    }
    final options = <_Subtab>[
      const _Subtab(GroupRoute.profile, 'Profile'),
      if (!group.automatic) const _Subtab(GroupRoute.membership, 'Membership'),
      const _Subtab(GroupRoute.interaction, 'Interaction'),
      if (!group.automatic && data.smtpEnabled)
        const _Subtab(GroupRoute.email, 'Email'),
      const _Subtab(GroupRoute.categories, 'Categories'),
      if (data.taggingEnabled) const _Subtab(GroupRoute.tags, 'Tags'),
      const _Subtab(GroupRoute.logs, 'Logs'),
    ];
    final selected = options.any((option) => option.value == route.subsection)
        ? route.subsection!
        : GroupRoute.profile;

    return Column(
      children: [
        _Subtabs(
          selected: selected,
          options: options,
          onSelect: (subsection) => onSelect(
            GroupRoute.detail(
              group.name,
              section: GroupRoute.manage,
              subsection: subsection,
            ),
          ),
        ),
        Expanded(
          child: selected == GroupRoute.logs
              ? _GroupLogs(
                  page: data.logs,
                  loading: data.sectionLoading,
                  loadingMore: data.loadingMore,
                  error: data.sectionError,
                  onLoadMore: onLoadMore,
                )
              : _GroupManageForm(
                  key: ValueKey('group-manage-form-${group.id}-$selected'),
                  group: group,
                  subsection: selected,
                  saving: data.saving,
                  onSave: onSave,
                ),
        ),
      ],
    );
  }
}

class _GroupManageForm extends StatefulWidget {
  const _GroupManageForm({
    super.key,
    required this.group,
    required this.subsection,
    required this.saving,
    required this.onSave,
  });

  final Group group;
  final String subsection;
  final bool saving;
  final Future<void> Function(GroupManageUpdate)? onSave;

  @override
  State<_GroupManageForm> createState() => _GroupManageFormState();
}

class _GroupManageFormState extends State<_GroupManageForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _text = {};
  late bool _publicExit;
  late bool _publishReadState;
  late bool _smtpEnabled;
  late bool _allowUnknownSenderReplies;
  late int _visibility;
  late int _membersVisibility;
  late int _mentionable;
  late int _messageable;
  late int _defaultNotification;
  late String _admission;

  Group get group => widget.group;

  @override
  void initState() {
    super.initState();
    void value(String key, Object? value) =>
        _text[key] = TextEditingController(text: value?.toString() ?? '');
    value('name', group.name);
    value('full_name', group.fullName ?? group.displayName);
    value('bio_raw', group.bioRaw);
    value('title', group.title);
    value('flair_icon', group.flairIcon);
    value('flair_bg_color', group.flairBackgroundColor);
    value('flair_color', group.flairColor);
    value(
      'automatic_membership_email_domains',
      group.automaticMembershipEmailDomains,
    );
    value('membership_request_template', group.membershipRequestTemplate);
    value('associated_group_ids', group.associatedGroupIds.join(','));
    value('grant_trust_level', group.grantTrustLevel);
    value('incoming_email', group.incomingEmail);
    value('smtp_server', group.smtpServer);
    value('smtp_port', group.smtpPort);
    value('smtp_ssl_mode', group.smtpSslMode);
    value('email_username', group.emailUsername);
    value('email_password', '');
    value('email_from_alias', group.emailFromAlias);
    value('watching_category_ids', group.watchingCategoryIds.join(','));
    value('tracking_category_ids', group.trackingCategoryIds.join(','));
    value(
      'watching_first_post_category_ids',
      group.watchingFirstPostCategoryIds.join(','),
    );
    value('regular_category_ids', group.regularCategoryIds.join(','));
    value('muted_category_ids', group.mutedCategoryIds.join(','));
    value('watching_tags', group.watchingTags.map((tag) => tag.name).join(','));
    value('tracking_tags', group.trackingTags.map((tag) => tag.name).join(','));
    value(
      'watching_first_post_tags',
      group.watchingFirstPostTags.map((tag) => tag.name).join(','),
    );
    value('regular_tags', group.regularTags.map((tag) => tag.name).join(','));
    value('muted_tags', group.mutedTags.map((tag) => tag.name).join(','));

    _publicExit = group.publicExit;
    _publishReadState = group.publishReadState;
    _smtpEnabled = group.smtpEnabled;
    _allowUnknownSenderReplies = group.allowUnknownSenderTopicReplies;
    _visibility = group.visibilityLevel;
    _membersVisibility = group.membersVisibilityLevel;
    _mentionable = group.mentionableLevel;
    _messageable = group.messageableLevel;
    _defaultNotification = group.defaultNotificationLevel;
    _admission = group.publicAdmission
        ? 'free'
        : group.allowMembershipRequests
        ? 'request'
        : 'closed';
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(String key) => _text[key]!;

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final update = GroupManageUpdate(
      subsection: widget.subsection,
      values: _valuesForSubsection(),
    );
    await widget.onSave?.call(update);
  }

  Map<String, Object?> _valuesForSubsection() => switch (widget.subsection) {
    GroupRoute.profile => {
      'name': _value('name'),
      'full_name': _value('full_name'),
      'bio_raw': _value('bio_raw'),
      'title': _value('title'),
      'flair_icon': _value('flair_icon'),
      'flair_bg_color': _value('flair_bg_color'),
      'flair_color': _value('flair_color'),
    },
    GroupRoute.membership => {
      'public_admission': _admission == 'free',
      'allow_membership_requests': _admission == 'request',
      'public_exit': _publicExit,
      'visibility_level': _visibility,
      'members_visibility_level': _membersVisibility,
      'membership_request_template': _value('membership_request_template'),
      'automatic_membership_email_domains': _value(
        'automatic_membership_email_domains',
      ),
      'associated_group_ids': _integerList('associated_group_ids'),
      'grant_trust_level': _nullableInt('grant_trust_level'),
    },
    GroupRoute.interaction => {
      'mentionable_level': _mentionable,
      'messageable_level': _messageable,
      'publish_read_state': _publishReadState,
      'default_notification_level': _defaultNotification,
      'incoming_email': _value('incoming_email'),
    },
    GroupRoute.email => {
      'smtp_enabled': _smtpEnabled,
      'smtp_server': _value('smtp_server'),
      'smtp_port': _nullableInt('smtp_port'),
      'smtp_ssl_mode': _nullableInt('smtp_ssl_mode'),
      'email_username': _value('email_username'),
      if (_value('email_password').isNotEmpty)
        'email_password': _value('email_password'),
      'email_from_alias': _value('email_from_alias'),
      'allow_unknown_sender_topic_replies': _allowUnknownSenderReplies,
    },
    GroupRoute.categories => {
      for (final key in _categoryKeys) key: _integerList(key),
    },
    GroupRoute.tags => {for (final key in _tagKeys) key: _stringList(key)},
    _ => const <String, Object?>{},
  };

  String _value(String key) => _controller(key).text.trim();

  int? _nullableInt(String key) => int.tryParse(_value(key));

  List<int> _integerList(String key) => [
    for (final value in _value(key).split(','))
      if (int.tryParse(value.trim()) case final number? when number > 0) number,
  ];

  List<String> _stringList(String key) => [
    for (final value in _value(key).split(','))
      if (value.trim().isNotEmpty) value.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        key: PageStorageKey('group-manage-${widget.subsection}-scroll'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _manageFields(),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DButton(
                      key: ValueKey('save-group-${widget.subsection}'),
                      label: const Text('Save changes'),
                      loading: widget.saving,
                      variant: DButtonVariant.primary,
                      onPressed: widget.onSave == null ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _manageFields() => switch (widget.subsection) {
    GroupRoute.profile => _ProfileFields(group: group, controllers: _text),
    GroupRoute.membership => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Membership',
          description: 'Choose who can discover and join this group.',
        ),
        DropdownButtonFormField<String>(
          key: const ValueKey('membership-admission'),
          initialValue: _admission,
          decoration: const InputDecoration(labelText: 'Who can join?'),
          items: const [
            DropdownMenuItem(value: 'closed', child: Text('Invitation only')),
            DropdownMenuItem(value: 'request', child: Text('Request approval')),
            DropdownMenuItem(value: 'free', child: Text('Anyone can join')),
          ],
          onChanged: (value) => setState(() => _admission = value ?? 'closed'),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Members can leave'),
          value: _publicExit,
          onChanged: (value) => setState(() => _publicExit = value),
        ),
        _LevelField(
          label: 'Group visibility',
          value: _visibility,
          onChanged: (value) => setState(() => _visibility = value),
        ),
        _LevelField(
          label: 'Member-list visibility',
          value: _membersVisibility,
          onChanged: (value) => setState(() => _membersVisibility = value),
        ),
        _textField('membership_request_template', 'Request template', lines: 4),
        _textField(
          'automatic_membership_email_domains',
          'Automatic membership email domains',
          hint: 'example.com|another.example',
        ),
        _textField(
          'associated_group_ids',
          'Associated group IDs',
          hint: '12, 35',
        ),
        _textField('grant_trust_level', 'Grant trust level', numeric: true),
      ],
    ),
    GroupRoute.interaction => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Interaction',
          description: 'Control mentions, messages, and notification defaults.',
        ),
        _InteractionLevelField(
          label: 'Who can mention this group?',
          value: _mentionable,
          onChanged: (value) => setState(() => _mentionable = value),
        ),
        _InteractionLevelField(
          label: 'Who can message this group?',
          value: _messageable,
          onChanged: (value) => setState(() => _messageable = value),
        ),
        _LevelField(
          label: 'Default notification level',
          value: _defaultNotification,
          onChanged: (value) => setState(() => _defaultNotification = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Publish read state'),
          subtitle: const Text('Let members share message read state.'),
          value: _publishReadState,
          onChanged: (value) => setState(() => _publishReadState = value),
        ),
        _textField('incoming_email', 'Incoming email address'),
      ],
    ),
    GroupRoute.email => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Email',
          description: 'Configure the mailbox used by this group.',
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Enable SMTP'),
          value: _smtpEnabled,
          onChanged: (value) => setState(() => _smtpEnabled = value),
        ),
        _textField('smtp_server', 'SMTP server'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _textField('smtp_port', 'Port', numeric: true)),
            const SizedBox(width: 12),
            Expanded(
              child: _textField('smtp_ssl_mode', 'SSL mode', numeric: true),
            ),
          ],
        ),
        _textField('email_username', 'Username'),
        _textField(
          'email_password',
          'Password',
          obscure: true,
          hint: 'Leave blank to keep the existing password',
        ),
        _textField('email_from_alias', 'From alias'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow replies from unknown senders'),
          value: _allowUnknownSenderReplies,
          onChanged: (value) =>
              setState(() => _allowUnknownSenderReplies = value),
        ),
      ],
    ),
    GroupRoute.categories => _ListNotificationFields(
      title: 'Category notifications',
      description: 'Enter comma-separated category IDs for each level.',
      keys: _categoryKeys,
      controllers: _text,
    ),
    GroupRoute.tags => _ListNotificationFields(
      title: 'Tag notifications',
      description: 'Enter comma-separated tag names for each level.',
      keys: _tagKeys,
      controllers: _text,
    ),
    _ => const SizedBox.shrink(),
  };

  Widget _textField(
    String key,
    String label, {
    String? hint,
    int lines = 1,
    bool numeric = false,
    bool obscure = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey('group-field-$key'),
      controller: _controller(key),
      minLines: obscure ? 1 : lines,
      maxLines: obscure ? 1 : lines,
      obscureText: obscure,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

const _categoryKeys = [
  'watching_category_ids',
  'tracking_category_ids',
  'watching_first_post_category_ids',
  'regular_category_ids',
  'muted_category_ids',
];

const _tagKeys = [
  'watching_tags',
  'tracking_tags',
  'watching_first_post_tags',
  'regular_tags',
  'muted_tags',
];

class _ProfileFields extends StatelessWidget {
  const _ProfileFields({required this.group, required this.controllers});

  final Group group;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, {int lines = 1, String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            key: ValueKey('group-field-$key'),
            controller: controllers[key],
            minLines: lines,
            maxLines: lines,
            enabled: key != 'name' || !group.automatic,
            decoration: InputDecoration(labelText: label, hintText: hint),
            validator: key == 'name'
                ? (value) => value == null || value.trim().isEmpty
                      ? 'Enter a group name.'
                      : null
                : null,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FormHeading(
          title: 'Profile',
          description: 'The name and identity people see around the forum.',
        ),
        field('name', 'Group name'),
        field('full_name', 'Full name'),
        field('bio_raw', 'About this group', lines: 6),
        field('title', 'Member title'),
        field('flair_icon', 'Flair icon', hint: 'shield-halved'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field('flair_bg_color', 'Flair background')),
            const SizedBox(width: 12),
            Expanded(child: field('flair_color', 'Flair foreground')),
          ],
        ),
      ],
    );
  }
}

class _ListNotificationFields extends StatelessWidget {
  const _ListNotificationFields({
    required this.title,
    required this.description,
    required this.keys,
    required this.controllers,
  });

  final String title;
  final String description;
  final List<String> keys;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _FormHeading(title: title, description: description),
      for (final key in keys)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            key: ValueKey('group-field-$key'),
            controller: controllers[key],
            decoration: InputDecoration(labelText: _fieldLabel(key)),
          ),
        ),
    ],
  );
}

class _FormHeading extends StatelessWidget {
  const _FormHeading({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _LevelField extends StatelessWidget {
  const _LevelField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = <int>{0, 1, 2, 3, 4, value}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in values)
            DropdownMenuItem(value: option, child: Text(_levelLabel(option))),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}

class _InteractionLevelField extends StatelessWidget {
  const _InteractionLevelField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = <int>{0, 1, 2, 3, 4, 99, value}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in values)
            DropdownMenuItem(value: option, child: Text(_levelLabel(option))),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}

class _GroupLogs extends StatelessWidget {
  const _GroupLogs({
    required this.page,
    required this.loading,
    required this.loadingMore,
    required this.error,
    required this.onLoadMore,
  });

  final GroupLogsPage? page;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (page == null) {
      if (error != null) {
        return _GroupState(icon: DIcons.triangleExclamation, title: error!);
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (page!.logs.isEmpty && !loading) {
      return const _GroupState(
        icon: DIcons.farClock,
        title: 'No group changes have been recorded.',
      );
    }
    return ListView.separated(
      key: const PageStorageKey('group-logs-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: page!.logs.length + (!page!.allLoaded ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == page!.logs.length) {
          return _LoadMoreRow(loading: loadingMore, onPressed: onLoadMore);
        }
        final log = page!.logs[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListTile(
              leading: const DIcon(DIcons.farClock, size: 17),
              title: Text(_humanizeLog(log.action)),
              subtitle: Text(
                [
                  if (log.actingUser case final user?) '@${user.username}',
                  if (log.targetUser case final user?) '→ @${user.username}',
                  ?log.subject,
                  if (log.previousValue != null || log.newValue != null)
                    '${log.previousValue ?? '—'} → ${log.newValue ?? '—'}',
                ].join('  '),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

class _GroupState extends StatelessWidget {
  const _GroupState({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final DIconData icon;
  final String title;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DIcon(icon, size: 34),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 14),
            DButton(
              label: Text(actionLabel!),
              onPressed: onAction == null ? null : () => unawaited(onAction!()),
            ),
          ],
        ],
      ),
    ),
  );
}

String _fieldLabel(String key) {
  final words = key
      .replaceAll('_category_ids', '')
      .replaceAll('_tags', '')
      .replaceAll('_', ' ');
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

String _levelLabel(int value) => switch (value) {
  0 => 'Everyone',
  1 => 'Logged-in users',
  2 => 'Group members',
  3 => 'Group owners',
  4 => 'Staff',
  99 => 'Nobody',
  _ => 'Level $value',
};

String _humanizeLog(String action) {
  final words = action.replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'Group changed';
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
