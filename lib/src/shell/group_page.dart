import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group.dart';
import '../models/group_route.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/site_plugin_api.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'shell_scope.dart';

enum GroupMembershipAction { join, leave, request }

enum GroupRequestAction { accept, deny }

/// A field-level update from one native group-management subsection.
@immutable
final class GroupManageUpdate {
  const GroupManageUpdate({required this.subsection, required this.values});

  final String subsection;
  final Map<String, Object?> values;
}

/// Render state for one native group route.
///
/// Each section keeps its confirmed rows while a refresh is running. That is
/// why loading/error flags live beside, rather than instead of, the payloads.
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
    this.isAdmin = false,
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
  final bool isAdmin;
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

/// Native `/g/:name` shell.
///
/// Topic feeds remain owned by the shell and are injected through
/// [topicFeed]/[messageFeed]. Group-specific payloads and writes are projected
/// through callbacks, which keeps this view independent from controller cache
/// layout while still using [ShellScope] as the navigation default.
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
    this.onOpenMember,
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
  final ValueChanged<GroupMember>? onOpenMember;
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
          group: group,
          mutating: widget.data.mutating,
          onMembershipAction: widget.onMembershipAction,
          onMessageGroup: widget.onMessageGroup,
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
        page: widget.data.members,
        group: group,
        loading: widget.data.sectionLoading,
        loadingMore: widget.data.loadingMore,
        hasMore: widget.data.hasMore,
        error: widget.data.sectionError,
        onOpenMember: widget.onOpenMember,
        onLoadMore: widget.onLoadMore,
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

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.mutating,
    required this.onMembershipAction,
    required this.onMessageGroup,
  });

  final Group group;
  final bool mutating;
  final Future<void> Function(GroupMembershipAction action)? onMembershipAction;
  final VoidCallback? onMessageGroup;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GroupAvatar(group: group, size: 54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.label,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '@${group.name}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (actionLabel != null)
                      DButton(
                        key: ValueKey('group-${membershipAction!.name}'),
                        label: Text(actionLabel),
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
                    if (group.messageable && onMessageGroup != null) ...[
                      const SizedBox(width: 8),
                      DButton.iconOnly(
                        key: const ValueKey('group-message'),
                        icon: const DIcon(DIcons.envelope, size: 16),
                        tooltip: 'Message group',
                        onPressed: onMessageGroup,
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
                    if (group.userCount case final count?)
                      _HeaderFact(icon: DIcons.users, label: '$count members'),
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
              ],
            ),
          ),
        ),
      ),
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

class _MembersSection extends StatelessWidget {
  const _MembersSection({
    required this.page,
    required this.group,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.error,
    required this.onOpenMember,
    required this.onLoadMore,
  });

  final GroupMembersPage? page;
  final Group group;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;
  final ValueChanged<GroupMember>? onOpenMember;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!group.canSeeMembers) {
      return const _GroupState(
        icon: DIcons.lock,
        title: 'This group’s members are private.',
      );
    }
    if (page == null) {
      if (error != null) {
        return _GroupState(icon: DIcons.triangleExclamation, title: error!);
      }
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (page!.members.isEmpty && !loading) {
      return const _GroupState(
        icon: DIcons.users,
        title: 'This group has no members.',
      );
    }

    return ListView.separated(
      key: const PageStorageKey('group-members-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      itemCount: page!.members.length + (hasMore || loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == page!.members.length) {
          return _LoadMoreRow(loading: loadingMore, onPressed: onLoadMore);
        }
        final member = page!.members[index];
        return _MemberCard(
          member: member,
          onTap: () => onOpenMember?.call(member),
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onTap});

  final GroupMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
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
                  ClipOval(
                    child: AvatarImage(
                      url: member.avatarUrl,
                      size: 42,
                      fallback: CircleAvatar(
                        radius: 21,
                        child: Text(
                          member.username.characters.firstOrNull
                                  ?.toUpperCase() ??
                              '?',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name?.trim().isNotEmpty == true
                              ? member.name!
                              : member.username,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '@${member.username}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (member.title case final title?)
                          Text(title, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (member.owner)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('Owner'),
                    )
                  else if (member.primary)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('Primary'),
                    ),
                  const SizedBox(width: 6),
                  const DIcon(DIcons.chevronRight, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
