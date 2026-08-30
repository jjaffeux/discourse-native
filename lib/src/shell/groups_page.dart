import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'shell_scope.dart';

/// Sorts exposed by Discourse's group directory.
enum GroupDirectoryOrder {
  name('name', 'Name'),
  memberCount('user_count', 'Members');

  const GroupDirectoryOrder(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// Render state for the native `/g` directory.
///
/// Loading and mutation ownership deliberately remain outside the widget. The
/// groups controller can replace this immutable value without making the page
/// depend on its cache implementation.
@immutable
final class GroupsPageData {
  const GroupsPageData({
    this.groups = const [],
    this.typeFilters = const [],
    this.totalRows = 0,
    this.query = '',
    this.type,
    this.order = GroupDirectoryOrder.name,
    this.ascending = true,
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
  final GroupDirectoryOrder order;
  final bool ascending;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final bool hasMore;
  final String? error;
  final bool pageError;
  final bool canCreateGroup;
}

/// Native group directory with server-backed search, type and sort controls.
class GroupsPage extends StatefulWidget {
  const GroupsPage({
    super.key,
    required this.siteUrl,
    required this.data,
    this.onSearchChanged,
    this.onTypeChanged,
    this.onOrderChanged,
    this.onAscendingChanged,
    this.onRefresh,
    this.onLoadMore,
    this.onOpenGroup,
    this.onCreateGroup,
  });

  final String siteUrl;
  final GroupsPageData data;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String?>? onTypeChanged;
  final ValueChanged<GroupDirectoryOrder>? onOrderChanged;
  final ValueChanged<bool>? onAscendingChanged;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final ValueChanged<Group>? onOpenGroup;
  final VoidCallback? onCreateGroup;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.data.query);
  }

  @override
  void didUpdateWidget(GroupsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_searchFocus.hasFocus && widget.data.query != _searchController.text) {
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

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 &&
        notification.metrics.extentAfter < 480 &&
        widget.data.hasMore &&
        !widget.data.loading &&
        !widget.data.loadingMore) {
      widget.onLoadMore?.call();
    }
    return false;
  }

  Future<void> _refresh() async {
    await widget.onRefresh?.call();
  }

  void _openGroup(Group group) {
    if (widget.onOpenGroup case final callback?) {
      callback(group);
      return;
    }
    ShellScope.maybeRead(
      context,
    )?.openGroupUrl(Uri(pathSegments: ['g', group.name]).path);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (!data.loaded && data.groups.isEmpty && data.loading) {
      return const Center(
        child: CircularProgressIndicator.adaptive(
          key: ValueKey('groups-loading'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomScrollView(
          key: const PageStorageKey('groups-directory-scroll'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: _DirectoryControls(
                      data: data,
                      searchController: _searchController,
                      searchFocus: _searchFocus,
                      onSearchChanged: _search,
                      onSearchSubmitted: _submitSearch,
                      onTypeChanged: widget.onTypeChanged,
                      onOrderChanged: widget.onOrderChanged,
                      onAscendingChanged: widget.onAscendingChanged,
                      onCreateGroup: widget.onCreateGroup,
                    ),
                  ),
                ),
              ),
            ),
            if (data.loading && data.groups.isNotEmpty)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (data.error != null && (!data.pageError || data.groups.isEmpty))
              SliverToBoxAdapter(
                child: _DirectoryError(
                  message: data.error!,
                  onRetry: widget.onRefresh,
                ),
              ),
            if (data.groups.isEmpty && data.loaded && data.error == null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyDirectory(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width >= 980
                        ? 3
                        : width >= 620
                        ? 2
                        : 1;
                    return SliverGrid.builder(
                      itemCount: data.groups.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        mainAxisExtent: 170,
                      ),
                      itemBuilder: (context, index) {
                        final group = data.groups[index];
                        return _GroupDirectoryCard(
                          key: ValueKey('group-card-${group.name}'),
                          group: group,
                          onTap: () => _openGroup(group),
                        );
                      },
                    );
                  },
                ),
              ),
            if (data.loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
                ),
              ),
            if (data.pageError && data.error != null)
              SliverToBoxAdapter(
                child: _DirectoryError(
                  message: data.error!,
                  onRetry: widget.onLoadMore,
                ),
              ),
            if (data.hasMore && !data.loadingMore && data.groups.isNotEmpty)
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
    required this.onOrderChanged,
    required this.onAscendingChanged,
    required this.onCreateGroup,
  });

  final GroupsPageData data;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<String?>? onTypeChanged;
  final ValueChanged<GroupDirectoryOrder>? onOrderChanged;
  final ValueChanged<bool>? onAscendingChanged;
  final VoidCallback? onCreateGroup;

  @override
  Widget build(BuildContext context) {
    final resultLabel = data.totalRows == 1
        ? '1 group'
        : '${data.totalRows} groups';
    final types = <String>{...data.typeFilters};
    if (data.type case final selected?) types.add(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Groups',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resultLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (data.canCreateGroup)
              DButton(
                key: const ValueKey('create-group'),
                label: const Text('New group'),
                icon: const DIcon(DIcons.plus, size: 16),
                variant: DButtonVariant.primary,
                onPressed: onCreateGroup,
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('groups-search'),
          controller: searchController,
          focusNode: searchFocus,
          onChanged: onSearchChanged,
          onSubmitted: onSearchSubmitted,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search groups',
            hintText: 'Name or description',
            prefixIcon: const DIcon(DIcons.magnifyingGlass, size: 16),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      searchController.clear();
                      onSearchSubmitted('');
                    },
                    icon: const DIcon(DIcons.xmark, size: 16),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              key: const ValueKey('group-type-all'),
              label: const Text('All'),
              selected: data.type == null,
              onSelected: (_) => onTypeChanged?.call(null),
            ),
            for (final type in types)
              ChoiceChip(
                key: ValueKey('group-type-$type'),
                label: Text(_humanize(type)),
                selected: data.type == type,
                onSelected: (_) => onTypeChanged?.call(type),
              ),
            const SizedBox(width: 8),
            DropdownButton<GroupDirectoryOrder>(
              key: const ValueKey('groups-order'),
              value: data.order,
              underline: const SizedBox.shrink(),
              onChanged: onOrderChanged == null
                  ? null
                  : (value) {
                      if (value != null) onOrderChanged!(value);
                    },
              items: [
                for (final order in GroupDirectoryOrder.values)
                  DropdownMenuItem(value: order, child: Text(order.label)),
              ],
            ),
            IconButton(
              key: const ValueKey('groups-order-direction'),
              tooltip: data.ascending ? 'Sort descending' : 'Sort ascending',
              onPressed: onAscendingChanged == null
                  ? null
                  : () => onAscendingChanged!(!data.ascending),
              icon: Icon(
                data.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 19,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupDirectoryCard extends StatelessWidget {
  const _GroupDirectoryCard({
    super.key,
    required this.group,
    required this.onTap,
  });

  final Group group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bio = group.plainBio ?? group.bioExcerpt;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: 'Open ${group.label}',
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _GroupMark(group: group, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '@${group.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const DIcon(DIcons.chevronRight, size: 14),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Text(
                    bio?.trim().isNotEmpty == true
                        ? bio!.trim()
                        : 'No group description.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Row(
                  children: [
                    const DIcon(DIcons.users, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      group.userCount == null
                          ? 'Members hidden'
                          : '${group.userCount} members',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (group.isGroupOwner)
                      const _MembershipBadge(label: 'Owner')
                    else if (group.isGroupUser)
                      const _MembershipBadge(label: 'Member'),
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

class _GroupMark extends StatelessWidget {
  const _GroupMark({required this.group, required this.size});

  final Group group;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primaryContainer,
      ),
      child: Text(
        group.label.characters.firstOrNull?.toUpperCase() ?? 'G',
        style: TextStyle(
          color: colors.onPrimaryContainer,
          fontSize: size * .45,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MembershipBadge extends StatelessWidget {
  const _MembershipBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).shell.selected,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    ),
  );
}

class _DirectoryError extends StatelessWidget {
  const _DirectoryError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
            DButton(
              label: const Text('Try again'),
              onPressed: onRetry,
              variant: DButtonVariant.link,
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyDirectory extends StatelessWidget {
  const _EmptyDirectory();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DIcon(DIcons.users, size: 36),
          SizedBox(height: 12),
          Text('No groups match these filters.'),
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
