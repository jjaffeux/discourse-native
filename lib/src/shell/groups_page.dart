import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../utils/pagination.dart';
import 'avatar_image.dart';
import 'content_reading_lane.dart';
import 'site_url.dart';

@immutable
final class GroupsPageData {
  const GroupsPageData({
    this.groups = const [],
    this.typeFilters = const [],
    this.totalRows = 0,
    this.query = '',
    this.type,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.hasMore = false,
    this.error,
    this.pageError = false,
    this.canCreateGroup = false,
  });

  final List<Group> groups;
  final List<String> typeFilters;
  final int totalRows;
  final String query;
  final String? type;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final bool hasMore;
  final String? error;
  final bool pageError;
  final bool canCreateGroup;
}

class GroupsPage extends StatefulWidget {
  const GroupsPage({
    super.key,
    required this.siteUrl,
    required this.data,
    this.onSearchChanged,
    this.onTypeChanged,
    this.onRefresh,
    this.onLoadMore,
    this.onOpenGroup,
    this.onCreateGroup,
    this.loadMemberPreview,
  });

  final String siteUrl;
  final GroupsPageData data;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String?>? onTypeChanged;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final ValueChanged<Group>? onOpenGroup;
  final VoidCallback? onCreateGroup;
  final Future<List<GroupMember>> Function(Group group)? loadMemberPreview;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  bool _searchVisible = false;
  final Map<int, Future<List<GroupMember>>> _memberPreviews = {};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.data.query);
    _searchVisible = widget.data.query.isNotEmpty;
  }

  @override
  void didUpdateWidget(GroupsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final siteChanged = oldWidget.siteUrl != widget.siteUrl;
    if (siteChanged) {
      _searchDebounce?.cancel();
      _memberPreviews.clear();
      _searchVisible = widget.data.query.isNotEmpty;
    } else if (widget.data.query.isNotEmpty) {
      _searchVisible = true;
    }
    if (oldWidget.data.loading && !widget.data.loading) {
      _memberPreviews.clear();
    }
    if (siteChanged ||
        (!_searchFocus.hasFocus &&
            widget.data.query != _searchController.text)) {
      _searchController.value = TextEditingValue(
        text: widget.data.query,
        selection: TextSelection.collapsed(offset: widget.data.query.length),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => widget.onSearchChanged?.call(value.trim()),
    );
  }

  void _submitSearch(String value) {
    _searchDebounce?.cancel();
    widget.onSearchChanged?.call(value.trim());
  }

  // A failed page is retried only from its Try again row: every scroll
  // notification near the end would otherwise resend it as soon as it fails.
  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.extentAfter <
            paginationPrefetchDistance(notification.metrics) &&
        widget.data.hasMore &&
        !widget.data.loading &&
        !widget.data.loadingMore &&
        !widget.data.pageError) {
      widget.onLoadMore?.call();
    }
    return false;
  }

  void _showSearch() {
    setState(() => _searchVisible = true);
    _searchFocus.requestFocus();
  }

  Future<List<GroupMember>>? _memberPreview(Group group) {
    if (!group.canSeeMembers || group.userCount == 0) return null;
    final load = widget.loadMemberPreview;
    if (load == null) return null;
    return _memberPreviews.putIfAbsent(group.id, () => load(group));
  }

  void _openGroup(Group group) {
    widget.onOpenGroup?.call(group);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return ContentReadingLane(
      basePadding: const EdgeInsets.symmetric(horizontal: 16),
      builder: (context, lane) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: DScrollBar(
          controller: _scrollController,
          child: CustomScrollView(
            key: const PageStorageKey('groups-directory-scroll'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  left: lane.leftInset,
                  right: lane.rightInset,
                ),
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: _DirectoryControls(
                          data: data,
                          searchController: _searchController,
                          searchFocus: _searchFocus,
                          onSearchChanged: _search,
                          onSearchSubmitted: _submitSearch,
                          onTypeChanged: widget.onTypeChanged,
                          onCreateGroup: widget.onCreateGroup,
                          searchVisible: _searchVisible,
                          onShowSearch: _showSearch,
                        ),
                      ),
                    ),
                    if (data.error != null &&
                        (!data.pageError || data.groups.isEmpty))
                      SliverToBoxAdapter(
                        child: _DirectoryError(
                          message: data.error!,
                          onRetry: widget.onRefresh,
                        ),
                      ),
                    if (!data.loaded && data.groups.isEmpty && data.loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: SizedBox.shrink(key: ValueKey('groups-loading')),
                      )
                    else if (data.groups.isEmpty &&
                        data.loaded &&
                        data.error == null)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyDirectory(),
                      )
                    else
                      SliverList.separated(
                        itemCount: data.groups.length,
                        separatorBuilder: (context, index) =>
                            const DSeparator(),
                        itemBuilder: (context, index) {
                          final group = data.groups[index];
                          return _GroupDirectoryRow(
                            key: ValueKey('group-row-${group.name}'),
                            siteUrl: widget.siteUrl,
                            group: group,
                            memberPreview: _memberPreview(group),
                            onTap: () => _openGroup(group),
                          );
                        },
                      ),
                    if (data.pageError && data.error != null)
                      SliverToBoxAdapter(
                        child: _DirectoryError(
                          message: data.error!,
                          onRetry: widget.onLoadMore,
                        ),
                      ),
                    if (data.hasMore &&
                        !data.loadingMore &&
                        data.groups.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: Center(
                            child: DButton(
                              key: const ValueKey('groups-load-more'),
                              label: const Text('Load more'),
                              onPressed: widget.onLoadMore,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectoryControls extends StatelessWidget {
  const _DirectoryControls({
    required this.data,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onTypeChanged,
    required this.onCreateGroup,
    required this.searchVisible,
    required this.onShowSearch,
  });

  final GroupsPageData data;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<String?>? onTypeChanged;
  final VoidCallback? onCreateGroup;
  final bool searchVisible;
  final VoidCallback onShowSearch;

  @override
  Widget build(BuildContext context) {
    final types = <String>{...data.typeFilters};
    if (data.type case final selected?) types.add(selected);
    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: DSpacing.md,
            runSpacing: DSpacing.sm,
            children: [
              const DText('Groups', variant: DTextVariant.h3, headingLevel: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: DSpacing.controlGap,
                children: [
                  DButton.iconOnly(
                    key: const ValueKey('groups-show-search'),
                    icon: const DIcon(DIcons.magnifyingGlass),
                    tooltip: 'Search groups',
                    variant: DButtonVariant.transparentBackground,
                    onPressed: onShowSearch,
                  ),
                  if (data.canCreateGroup)
                    DButton.iconOnly(
                      key: const ValueKey('create-group'),
                      icon: const DIcon(DIcons.plus),
                      tooltip: 'New group',
                      variant: DButtonVariant.outline,
                      onPressed: onCreateGroup,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: DSpacing.lg),
          if (searchVisible) ...[
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) => DInput(
                key: const ValueKey('groups-search'),
                size: DControlSize.field,
                controller: searchController,
                focusNode: searchFocus,
                autofocus: true,
                onChanged: onSearchChanged,
                onSubmitted: onSearchSubmitted,
                textInputAction: TextInputAction.search,
                semanticLabel: 'Search groups',
                hintText: 'Search groups',
                prefix: const DIcon(DIcons.magnifyingGlass),
                suffix: value.text.isEmpty
                    ? null
                    : DButton.iconOnly(
                        onPressed: () {
                          searchController.clear();
                          onSearchSubmitted('');
                        },
                        variant: DButtonVariant.transparentBackground,
                        tooltip: 'Clear search',
                        icon: const DIcon(DIcons.xmark),
                      ),
              ),
            ),
            const SizedBox(height: DSpacing.md),
          ],
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: DSpacing.md,
            runSpacing: DSpacing.sm,
            children: [
              SizedBox(
                width: 180,
                child: DSelect<String>.controlled(
                  key: const ValueKey('groups-type-filter'),
                  size: DControlSize.filter,
                  value: data.type,
                  semanticLabel: 'Filter by group type',
                  entries: [
                    const DSelectOption(
                      value: null,
                      label: 'All groups',
                      child: Text('All groups'),
                    ),
                    for (final type in types)
                      DSelectOption(
                        value: type,
                        label: _groupTypeLabel(type),
                        child: Text(_groupTypeLabel(type)),
                      ),
                  ],
                  onChanged: onTypeChanged,
                ),
              ),
              if (data.loaded || data.groups.isNotEmpty)
                Text(
                  '${data.totalRows} ${data.totalRows == 1 ? 'group' : 'groups'}',
                  key: const ValueKey('groups-count'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: DTokens.of(context).mutedForeground,
                  ),
                ),
            ],
          ),
          const SizedBox(height: DSpacing.lg),
          const DSeparator(),
        ],
      ),
    );
  }
}

String _groupTypeLabel(String type) => switch (type) {
  'my' => 'My groups',
  'owner' => 'Groups I own',
  'public' => 'Public groups',
  'close' || 'closed' => 'Closed groups',
  'automatic' => 'Automatic groups',
  _ => '${_humanize(type)} groups',
};

class _GroupDirectoryRow extends StatelessWidget {
  const _GroupDirectoryRow({
    super.key,
    required this.siteUrl,
    required this.group,
    required this.memberPreview,
    required this.onTap,
  });

  final String siteUrl;
  final Group group;
  final Future<List<GroupMember>>? memberPreview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final bio = (group.plainBio ?? group.bioExcerpt)?.trim();
    final badge = group.isGroupOwner
        ? const _MembershipBadge(label: 'Owner')
        : group.isGroupUser
        ? const _MembershipBadge(label: 'Member')
        : null;
    return DItem(
      shape: DItemShape.fullWidth,
      selectionStyle: DItemSelectionStyle.leadingAccent,
      link: true,
      onPressed: onTap,
      children: [
        DItemContent(
          spacing: DSpacing.md,
          alignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final stackBadge =
                    constraints.maxWidth /
                        MediaQuery.textScalerOf(context).scale(1) <
                    300;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _GroupIdentityAvatar(siteUrl: siteUrl, group: group),
                        const SizedBox(width: DSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.label,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '@${group.name}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: tokens.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!stackBadge && badge != null) ...[
                          const SizedBox(width: DSpacing.md),
                          badge,
                        ],
                      ],
                    ),
                    if (stackBadge && badge != null) ...[
                      const SizedBox(height: DSpacing.sm),
                      badge,
                    ],
                  ],
                );
              },
            ),
            if (bio != null && bio.isNotEmpty)
              Text(
                bio,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.mutedForeground,
                ),
              ),
            FutureBuilder<List<GroupMember>>(
              // A different future must not retain a previous account's avatars.
              key: ObjectKey(memberPreview),
              future: memberPreview,
              builder: (context, snapshot) => Wrap(
                spacing: DSpacing.sm,
                runSpacing: DSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (snapshot.data case final members? when members.isNotEmpty)
                    DAvatarGroup(
                      size: DAvatarSize.sm,
                      children: [
                        for (final member in members.take(4))
                          DAvatar(
                            semanticLabel: member.username,
                            child: AvatarImage(
                              url: member.avatarUrl,
                              size: DAvatarSize.sm.dimension,
                              fallback: DAvatarFallback(
                                child: Text(
                                  member.username.characters.firstOrNull
                                          ?.toUpperCase() ??
                                      '?',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  Text(
                    group.userCount == null
                        ? 'Members hidden'
                        : '${group.userCount} ${group.userCount == 1 ? 'member' : 'members'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: tokens.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupIdentityAvatar extends StatelessWidget {
  const _GroupIdentityAvatar({required this.siteUrl, required this.group});

  final String siteUrl;
  final Group group;

  @override
  Widget build(BuildContext context) {
    final flair = group.flairUrl?.trim();
    final imageUrl = flair != null && flair.contains('/')
        ? resolveSitePath(siteUrl, flair)
        : null;
    final icon =
        pluginIconNamed(context, group.flairIcon?.trim()) ??
        pluginIconNamed(context, flair);
    final fallback = DAvatarFallback(
      backgroundColor: _flairColor(group.flairBackgroundColor),
      foregroundColor: _flairColor(group.flairColor),
      child: icon == null
          ? Text(group.name.characters.firstOrNull?.toUpperCase() ?? '?')
          : DIcon(icon),
    );
    return DAvatar(
      size: DAvatarSize.lg,
      decorative: true,
      child: imageUrl == null
          ? fallback
          : AvatarImage(
              url: imageUrl,
              size: DAvatarSize.lg.dimension,
              fit: BoxFit.contain,
              fallback: fallback,
            ),
    );
  }
}

Color? _flairColor(String? value) {
  var hex = value?.trim().replaceFirst('#', '');
  if (hex == null) return null;
  if (hex.length == 3) {
    hex = hex.split('').map((digit) => '$digit$digit').join();
  }
  if (hex.length != 6) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(0xFF000000 | parsed);
}

class _MembershipBadge extends StatelessWidget {
  const _MembershipBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) =>
      DBadge(variant: DBadgeVariant.outline, child: Text(label));
}

class _DirectoryError extends StatelessWidget {
  const _DirectoryError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: DAlert(
      variant: DAlertVariant.destructive,
      icon: const DIcon(DIcons.triangleExclamation),
      description: DAlertDescription(child: Text(message)),
      action: DAlertAction(
        child: DButton(
          label: const Text('Try again'),
          onPressed: onRetry,
          variant: DButtonVariant.link,
        ),
      ),
    ),
  );
}

class _EmptyDirectory extends StatelessWidget {
  const _EmptyDirectory();

  @override
  Widget build(BuildContext context) => const Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(
                variant: DEmptyMediaVariant.icon,
                child: DIcon(DIcons.users),
              ),
              DEmptyTitle('No groups match these filters.'),
            ],
          ),
        ],
      ),
    ),
  );
}

String _humanize(String value) {
  final words = value.replaceAll(RegExp(r'[-_]'), ' ').trim();
  if (words.isEmpty) return value;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}
