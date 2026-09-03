part of '../group_page.dart';

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
  late final GroupMemberFilterController controller;
  bool _loadMorePending = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.metrics.extentAfter >= 480) {
      if (!widget.loadingMore) _loadMorePending = false;
      return false;
    }
    final onLoadMore = widget.onLoadMore;
    if (!_loadMorePending &&
        widget.hasMore &&
        !widget.loading &&
        !widget.loadingMore &&
        onLoadMore != null) {
      _loadMorePending = true;
      onLoadMore();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    controller = GroupMemberFilterController(
      filter: widget.filter,
      onFilterChanged: widget.onFilterChanged,
    );
  }

  @override
  void didUpdateWidget(_MembersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hasMore ||
        oldWidget.page?.members.length != widget.page?.members.length ||
        (oldWidget.loadingMore &&
            !widget.loadingMore &&
            widget.error == null) ||
        oldWidget.filter != widget.filter ||
        oldWidget.order != widget.order ||
        oldWidget.ascending != widget.ascending) {
      _loadMorePending = false;
    }
    controller.update(
      filter: widget.filter,
      onFilterChanged: widget.onFilterChanged,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
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
          controller: controller.searchController,
          canManage: widget.group.canManage,
          canInvite: widget.canInviteToForum,
          mutating: widget.mutating,
          onSearch: controller.search,
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
        final extra = widget.loadingMore ? 1 : 0;
        return ContentReadingLane(
          basePadding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          builder: (context, lane) => NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: ListView.separated(
              key: const PageStorageKey('group-members-scroll'),
              padding: lane.padding,
              itemCount: page.members.length + extra + 1,
              separatorBuilder: (_, _) => desktop
                  ? Divider(height: 1, color: Theme.of(context).shell.divider)
                  : const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _MemberTableHeader(
                    order: widget.order,
                    ascending: widget.ascending,
                    desktop: desktop,
                    onSortChanged: widget.onSortChanged,
                  );
                }
                final memberIndex = index - 1;
                if (memberIndex == page.members.length) {
                  return const _MembersLoadingMoreRow();
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
            ),
          ),
        );
      },
    );
  }
}

class _MembersLoadingMoreRow extends StatelessWidget {
  const _MembersLoadingMoreRow();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Loading more members',
    child: const Padding(
      padding: EdgeInsets.all(20),
      child: Center(
        child: SizedBox.square(
          key: ValueKey('group-members-loading-more'),
          dimension: 22,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      ),
    ),
  );
}

class _MembersToolbar extends StatelessWidget {
  const _MembersToolbar({
    required this.controller,
    required this.canManage,
    required this.canInvite,
    required this.mutating,
    required this.onSearch,
    required this.onAddMembers,
    required this.onInviteMembers,
  });

  final TextEditingController controller;
  final bool canManage;
  final bool canInvite;
  final bool mutating;
  final ValueChanged<String> onSearch;
  final VoidCallback? onAddMembers;
  final VoidCallback? onInviteMembers;

  @override
  Widget build(BuildContext context) => ContentReadingLaneBox(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          key: const ValueKey('group-member-search'),
          controller: controller,
          onChanged: onSearch,
          style: Theme.of(context).textTheme.labelLarge,
          decoration: _groupSearchDecoration('Search members'),
        );
        final actions = [
          if (canManage)
            DButton(
              key: const ValueKey('add-group-members'),
              icon: const DIcon(DIcons.userPlus, size: 16),
              label: const Text('Add members'),
              loading: mutating,
              onPressed: onAddMembers,
            ),
          if (canInvite)
            DButton(
              key: const ValueKey('invite-group-members'),
              icon: const DIcon(DIcons.paperPlane, size: 16),
              label: const Text('Invite'),
              onPressed: onInviteMembers,
            ),
        ];
        if (actions.isEmpty) return search;
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            for (final action in actions) ...[const SizedBox(width: 8), action],
          ],
        );
      },
    ),
  );
}

class _MemberTableHeader extends StatelessWidget {
  const _MemberTableHeader({
    required this.order,
    required this.ascending,
    required this.desktop,
    required this.onSortChanged,
  });

  final String order;
  final bool ascending;
  final bool desktop;
  final GroupMemberSortChanged? onSortChanged;

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (final (value, label) in const [
        ('username_lower', 'Member'),
        ('added_at', 'Added'),
        ('last_posted_at', 'Last post'),
        ('last_seen_at', 'Last seen'),
      ])
        _MemberSortHeader(
          value: value,
          label: label,
          selected: order == value,
          ascending: ascending,
          onPressed: onSortChanged == null
              ? null
              : () => onSortChanged!(
                  value,
                  order == value ? !ascending : value == 'username_lower',
                ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: desktop
          ? Row(
              children: [
                Expanded(flex: 5, child: columns[0]),
                Expanded(flex: 2, child: columns[1]),
                Expanded(flex: 2, child: columns[2]),
                Expanded(flex: 2, child: columns[3]),
                const SizedBox(width: 48),
              ],
            )
          : Wrap(spacing: 16, children: columns),
    );
  }
}

class _MemberSortHeader extends StatelessWidget {
  const _MemberSortHeader({
    required this.value,
    required this.label,
    required this.selected,
    required this.ascending,
    required this.onPressed,
  });

  final String value;
  final String label;
  final bool selected;
  final bool ascending;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey('group-member-sort-$value'),
    header: true,
    button: true,
    enabled: onPressed != null,
    value: selected
        ? (ascending ? 'Sorted ascending' : 'Sorted descending')
        : null,
    child: Tooltip(
      message: 'Sort by $label',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                RotatedBox(
                  quarterTurns: ascending ? 0 : 2,
                  child: const DIcon(DIcons.arrowUp, size: 12),
                ),
              ],
            ],
          ),
        ),
      ),
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
  late final GroupMemberAdditionController controller;

  @override
  void initState() {
    super.initState();
    controller = GroupMemberAdditionController(
      searchUsers: widget.searchUsers,
      addMembers: widget.onAdd,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (await controller.save() && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final email = controller.normalizedEmail;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('add-members-search'),
            autofocus: true,
            onChanged: controller.search,
            style: Theme.of(context).textTheme.labelLarge,
            decoration: _groupSearchDecoration('Username or email address'),
          ),
          const SizedBox(height: 10),
          if (controller.queryIsEmail)
            CheckboxListTile(
              key: ValueKey('add-email-$email'),
              contentPadding: EdgeInsets.zero,
              value: controller.selectedEmails.contains(email),
              title: Text(email),
              subtitle: const Text('Add by email address'),
              onChanged: (selected) =>
                  controller.toggleEmail(email, selected: selected == true),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: controller.results.length,
              itemBuilder: (context, index) {
                final user = controller.results[index];
                return CheckboxListTile(
                  key: ValueKey('add-user-${user.username}'),
                  contentPadding: EdgeInsets.zero,
                  value: controller.selectedUsernames.contains(user.username),
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
                  onChanged: (selected) => controller.toggleUsername(
                    user.username,
                    selected: selected == true,
                  ),
                );
              },
            ),
          ),
          if (controller.error case final error?) ...[
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
              controller.selectionCount == 1 ? 'Add member' : 'Add members',
            ),
            variant: DButtonVariant.primary,
            loading: controller.saving,
            onPressed: controller.canSave ? _save : null,
          ),
        ],
      );
    },
  );
}

class _InviteGroupSheet extends StatefulWidget {
  const _InviteGroupSheet({required this.siteUrl, required this.onCreate});

  final String siteUrl;
  final GroupCreateInvite onCreate;

  @override
  State<_InviteGroupSheet> createState() => _InviteGroupSheetState();
}

class _InviteGroupSheetState extends State<_InviteGroupSheet> {
  late final GroupInviteController controller;

  @override
  void initState() {
    super.initState();
    controller = GroupInviteController(
      siteUrl: widget.siteUrl,
      createInvite: widget.onCreate,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final normalizedEmail = controller.email.text.trim();
    final result = await controller.create();
    if (!mounted || result != GroupInviteSubmission.sent) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invitation sent to $normalizedEmail.')),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
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
          controller: controller.email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email (optional)'),
        ),
        if (controller.hasEmail) ...[
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('group-invite-message'),
            controller: controller.message,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Message (optional)'),
          ),
        ],
        if (controller.link case final link?) ...[
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
        if (controller.error case final error?) ...[
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (controller.link == null) ...[
          const SizedBox(height: 14),
          DButton(
            key: const ValueKey('create-group-invite'),
            icon: const DIcon(DIcons.paperPlane, size: 15),
            label: Text(controller.hasEmail ? 'Send invite' : 'Create link'),
            variant: DButtonVariant.primary,
            loading: controller.saving,
            onPressed: _create,
          ),
        ],
      ],
    ),
  );
}
