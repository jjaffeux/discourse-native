part of '../group_page.dart';

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
    return ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      builder: (context, lane) => ListView.separated(
        key: PageStorageKey('group-activity-$kind-scroll'),
        padding: lane.padding,
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
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
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
      ),
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
    return ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      builder: (context, lane) => ListView.separated(
        key: const PageStorageKey('group-requests-scroll'),
        padding: lane.padding,
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
                                    onAction!(
                                      requester,
                                      GroupRequestAction.deny,
                                    ),
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
      ),
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
    return ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      builder: (context, lane) => ListView.separated(
        key: const PageStorageKey('group-permissions-scroll'),
        padding: lane.padding,
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
      ),
    );
  }
}
