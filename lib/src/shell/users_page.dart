import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../models/user_directory.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'choice_menu.dart';
import 'shell_scope.dart';
import 'user_card.dart';
import 'user_directory_controller.dart';

@immutable
final class UsersPageData {
  const UsersPageData({
    this.items = const [],
    this.columns = const [],
    this.availableColumns = const [],
    this.groupNames = const [],
    this.canManageColumns = false,
    this.updatingColumns = false,
    this.currentUsername,
    this.totalRows = 0,
    this.lastUpdatedAt,
    this.query = const UserDirectoryQuery(),
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.hasMore = false,
    this.error,
    this.pageError = false,
  });

  final List<UserDirectoryItem> items;
  final List<UserDirectoryColumn> columns;
  final List<UserDirectoryColumn> availableColumns;
  final List<String> groupNames;
  final bool canManageColumns;
  final bool updatingColumns;
  final String? currentUsername;
  final int totalRows;
  final DateTime? lastUpdatedAt;
  final UserDirectoryQuery query;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final bool hasMore;
  final String? error;
  final bool pageError;
}

class UsersDirectoryHost extends StatefulWidget {
  const UsersDirectoryHost({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<UsersDirectoryHost> createState() => _UsersDirectoryHostState();
}

class _UsersDirectoryHostState extends State<UsersDirectoryHost> {
  bool _loadScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(UsersDirectoryHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleLoad();
  }

  void _scheduleLoad() {
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted) return;
      final shell = ShellScope.read(context);
      final instance = shell.instanceFor(widget.siteUrl);
      if (instance != null) unawaited(shell.userDirectory.load(instance));
    });
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return ListenableBuilder(
      listenable: shell.userDirectory,
      builder: (context, _) {
        final instance = shell.instanceFor(widget.siteUrl);
        final query = shell.userDirectory.queryFor(widget.siteUrl);
        final state = shell.userDirectory.stateFor(widget.siteUrl, query);

        Future<void> reload({bool refresh = true, bool more = false}) async {
          if (instance == null) return;
          await shell.userDirectory.load(
            instance,
            refresh: refresh,
            more: more,
          );
        }

        void replaceQuery(UserDirectoryQuery next) {
          if (instance == null ||
              !shell.userDirectory.replaceQuery(widget.siteUrl, next)) {
            return;
          }
          unawaited(shell.userDirectory.load(instance, refresh: true));
        }

        return UsersPage(
          siteUrl: widget.siteUrl,
          data: UsersPageData(
            items: state.items,
            columns: state.columns,
            availableColumns: state.availableColumns,
            groupNames: state.groupNames,
            canManageColumns: state.canManageColumns,
            updatingColumns: shell.userDirectory.updatingColumnsFor(
              widget.siteUrl,
            ),
            currentUsername: instance?.user?.username,
            totalRows: state.totalRows,
            lastUpdatedAt: state.lastUpdatedAt,
            query: query,
            loading: state.loading,
            loadingMore: state.loadingMore,
            loaded: state.loaded,
            hasMore: state.hasMore,
            error: state.error,
            pageError: state.pageError,
          ),
          onPeriodChanged: (period) =>
              replaceQuery(query.copyWith(period: period)),
          onSearchChanged: (search) =>
              replaceQuery(query.copyWith(search: search)),
          onGroupChanged: (group) => replaceQuery(
            group == null ? query.withoutGroup() : query.copyWith(group: group),
          ),
          onSortChanged: (order, ascending) =>
              replaceQuery(query.copyWith(order: order, ascending: ascending)),
          onManageColumns: state.canManageColumns && instance != null
              ? (columns) =>
                    shell.userDirectory.updateColumns(instance, columns)
              : null,
          onRefresh: reload,
          onLoadMore: () => unawaited(reload(refresh: false, more: true)),
        );
      },
    );
  }
}

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.siteUrl,
    required this.data,
    this.onPeriodChanged,
    this.onSearchChanged,
    this.onGroupChanged,
    this.onSortChanged,
    this.onManageColumns,
    this.onRefresh,
    this.onLoadMore,
  });

  final String siteUrl;
  final UsersPageData data;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String?>? onGroupChanged;
  final void Function(String order, bool ascending)? onSortChanged;
  final Future<bool> Function(List<UserDirectoryColumn>)? onManageColumns;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  static const double _rowHeight = 56;
  static const double _headerHeight = 42;
  static const double _metricWidth = 132;

  late final TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _horizontal = ScrollController();
  final ScrollController _identityVertical = ScrollController();
  final ScrollController _metricsVertical = ScrollController();
  Timer? _searchDebounce;
  Set<int>? _visibleColumnIds;
  int? _hoveredId;
  bool _syncingVerticalScroll = false;
  bool _loadMoreCheckScheduled = false;
  bool _loadMoreRequested = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.data.query.search);
    _identityVertical.addListener(_identityScrolled);
    _metricsVertical.addListener(_metricsScrolled);
  }

  @override
  void didUpdateWidget(UsersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_searchFocus.hasFocus &&
        widget.data.query.search != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: widget.data.query.search,
        selection: TextSelection.collapsed(
          offset: widget.data.query.search.length,
        ),
      );
    }
    final oldIds = {for (final column in oldWidget.data.columns) column.id};
    final newIds = {for (final column in widget.data.columns) column.id};
    final configured = _visibleColumnIds;
    if (configured != null && !setEquals(oldIds, newIds)) {
      configured
        ..removeWhere((id) => !newIds.contains(id))
        ..addAll(newIds.difference(oldIds));
    }
    if (oldWidget.data.items.length != widget.data.items.length ||
        oldWidget.data.loadingMore != widget.data.loadingMore ||
        oldWidget.data.hasMore != widget.data.hasMore ||
        oldWidget.data.query != widget.data.query) {
      _loadMoreRequested = false;
      _scheduleLoadMoreCheck();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _horizontal.dispose();
    _identityVertical.dispose();
    _metricsVertical.dispose();
    super.dispose();
  }

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncingVerticalScroll || !source.hasClients || !target.hasClients) {
      return;
    }
    final offset = source.offset.clamp(
      target.position.minScrollExtent,
      target.position.maxScrollExtent,
    );
    if ((target.offset - offset).abs() < 0.5) return;
    _syncingVerticalScroll = true;
    target.jumpTo(offset);
    _syncingVerticalScroll = false;
  }

  void _identityScrolled() {
    _syncVertical(_identityVertical, _metricsVertical);
    _scheduleLoadMoreCheck();
  }

  void _metricsScrolled() {
    _syncVertical(_metricsVertical, _identityVertical);
    _scheduleLoadMoreCheck();
  }

  void _scheduleLoadMoreCheck() {
    if (_loadMoreCheckScheduled) return;
    _loadMoreCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreCheckScheduled = false;
      if (mounted) _maybeLoadMore();
    });
  }

  void _maybeLoadMore() {
    if (_loadMoreRequested ||
        widget.onLoadMore == null ||
        !widget.data.hasMore ||
        widget.data.loading ||
        widget.data.loadingMore ||
        widget.data.pageError) {
      return;
    }
    final position = _metricsVertical.hasClients
        ? _metricsVertical.position
        : _identityVertical.hasClients
        ? _identityVertical.position
        : null;
    if (position == null || position.extentAfter > _rowHeight * 5) return;
    _loadMoreRequested = true;
    widget.onLoadMore!();
  }

  void _search(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => widget.onSearchChanged?.call(value.trim()),
    );
  }

  void _submitSearch(String value) {
    _searchDebounce?.cancel();
    widget.onSearchChanged?.call(value.trim());
  }

  List<UserDirectoryColumn> get _visibleColumns {
    final selected = _visibleColumnIds;
    if (selected == null) return widget.data.columns;
    return [
      for (final column in widget.data.columns)
        if (selected.contains(column.id)) column,
    ];
  }

  void _sort(String order) {
    final query = widget.data.query;
    final ascending = query.order == order
        ? !query.ascending
        : order == 'username';
    widget.onSortChanged?.call(order, ascending);
  }

  Future<void> _chooseColumns() async {
    if (widget.data.canManageColumns &&
        widget.data.availableColumns.isNotEmpty &&
        widget.onManageColumns != null) {
      await _manageColumns();
      return;
    }
    await _chooseVisibleColumns();
  }

  Future<void> _chooseVisibleColumns() async {
    final draft = Set<int>.from(
      _visibleColumnIds ?? widget.data.columns.map((column) => column.id),
    );
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Visible columns'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          content: SizedBox(
            width: 360,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final column in widget.data.columns)
                    CheckboxListTile(
                      key: ValueKey('users-column-${column.id}'),
                      value: draft.contains(column.id),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(column.label),
                      onChanged: (visible) => updateDialog(() {
                        if (visible == true) {
                          draft.add(column.id);
                        } else {
                          draft.remove(column.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            DButton(
              onPressed: () => updateDialog(() {
                draft
                  ..clear()
                  ..addAll(widget.data.columns.map((column) => column.id));
              }),
              label: const Text('Show all'),
              variant: DButtonVariant.transparent,
            ),
            DButton(
              onPressed: () => Navigator.pop(dialogContext, draft),
              label: const Text('Done'),
              variant: DButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _visibleColumnIds = result);
  }

  Future<void> _manageColumns() async {
    var draft = [...widget.data.availableColumns]
      ..sort((a, b) => a.position.compareTo(b.position));
    final result = await showDialog<List<UserDirectoryColumn>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          final canSave = draft.any((column) => column.enabled);
          return AlertDialog(
            title: const Text('Directory columns'),
            contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            content: SizedBox(
              width: 440,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        'Choose which columns everyone sees and arrange their order.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (var index = 0; index < draft.length; index++)
                      CheckboxListTile(
                        key: ValueKey('users-manage-column-${draft[index].id}'),
                        value: draft[index].enabled,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(draft[index].label),
                        subtitle: Text(switch (draft[index].type) {
                          UserDirectoryColumnType.automatic => 'Activity',
                          UserDirectoryColumnType.userField => 'User field',
                          UserDirectoryColumnType.plugin => 'Plugin',
                        }),
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DButton.iconOnly(
                              key: ValueKey(
                                'users-column-up-${draft[index].id}',
                              ),
                              tooltip: 'Move ${draft[index].label} up',
                              onPressed: index == 0
                                  ? null
                                  : () => updateDialog(() {
                                      final moved = draft.removeAt(index);
                                      draft.insert(index - 1, moved);
                                      draft = [
                                        for (
                                          var draftIndex = 0;
                                          draftIndex < draft.length;
                                          draftIndex++
                                        )
                                          draft[draftIndex].copyWith(
                                            position: draftIndex + 1,
                                          ),
                                      ];
                                    }),
                              size: DButtonSize.small,
                              icon: const DIcon(DIcons.arrowUp, size: 13),
                            ),
                            const SizedBox(width: 6),
                            DButton.iconOnly(
                              key: ValueKey(
                                'users-column-down-${draft[index].id}',
                              ),
                              tooltip: 'Move ${draft[index].label} down',
                              onPressed: index == draft.length - 1
                                  ? null
                                  : () => updateDialog(() {
                                      final moved = draft.removeAt(index);
                                      draft.insert(index + 1, moved);
                                      draft = [
                                        for (
                                          var draftIndex = 0;
                                          draftIndex < draft.length;
                                          draftIndex++
                                        )
                                          draft[draftIndex].copyWith(
                                            position: draftIndex + 1,
                                          ),
                                      ];
                                    }),
                              size: DButtonSize.small,
                              icon: Transform.rotate(
                                angle: math.pi,
                                child: const DIcon(DIcons.arrowUp, size: 13),
                              ),
                            ),
                          ],
                        ),
                        onChanged: (enabled) => updateDialog(() {
                          draft[index] = draft[index].copyWith(
                            enabled: enabled ?? false,
                          );
                        }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              DButton(
                onPressed: () => Navigator.pop(dialogContext),
                label: const Text('Cancel'),
                variant: DButtonVariant.transparent,
              ),
              DButton(
                key: const ValueKey('users-save-columns'),
                onPressed: canSave
                    ? () => Navigator.pop(dialogContext, draft)
                    : null,
                label: const Text('Save'),
                variant: DButtonVariant.primary,
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    final saved = await widget.onManageColumns!(List.unmodifiable(result));
    if (!mounted || saved) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't update directory columns.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _MatrixPalette.of(context);
    final columns = _visibleColumns;
    _scheduleLoadMoreCheck();
    return ColoredBox(
      key: const ValueKey('users-page'),
      color: palette.surface,
      child: LayoutBuilder(
        builder: (context, constraints) => _DirectorySurface(
          siteUrl: widget.siteUrl,
          palette: palette,
          data: widget.data,
          columns: columns,
          compact: constraints.maxWidth < 720,
          searchController: _searchController,
          searchFocus: _searchFocus,
          horizontal: _horizontal,
          identityVertical: _identityVertical,
          metricsVertical: _metricsVertical,
          rowHeight: _rowHeight,
          headerHeight: _headerHeight,
          metricWidth: _metricWidth,
          hoveredId: _hoveredId,
          onHover: (id) {
            if (_hoveredId == id) return;
            setState(() => _hoveredId = id);
          },
          onSearchChanged: _search,
          onSearchSubmitted: _submitSearch,
          onClearSearch: () {
            _searchController.clear();
            _submitSearch('');
            setState(() {});
          },
          onPeriodChanged: widget.onPeriodChanged,
          onGroupChanged: widget.onGroupChanged,
          onSort: _sort,
          onChooseColumns: widget.data.updatingColumns ? null : _chooseColumns,
          onRefresh: widget.onRefresh,
        ),
      ),
    );
  }
}

class _DirectorySurface extends StatelessWidget {
  const _DirectorySurface({
    required this.siteUrl,
    required this.palette,
    required this.data,
    required this.columns,
    required this.compact,
    required this.searchController,
    required this.searchFocus,
    required this.horizontal,
    required this.identityVertical,
    required this.metricsVertical,
    required this.rowHeight,
    required this.headerHeight,
    required this.metricWidth,
    required this.hoveredId,
    required this.onHover,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onPeriodChanged,
    required this.onGroupChanged,
    required this.onSort,
    required this.onChooseColumns,
    required this.onRefresh,
  });

  final String siteUrl;
  final _MatrixPalette palette;
  final UsersPageData data;
  final List<UserDirectoryColumn> columns;
  final bool compact;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ScrollController horizontal;
  final ScrollController identityVertical;
  final ScrollController metricsVertical;
  final double rowHeight;
  final double headerHeight;
  final double metricWidth;
  final int? hoveredId;
  final ValueChanged<int?> onHover;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;
  final ValueChanged<String?>? onGroupChanged;
  final ValueChanged<String> onSort;
  final VoidCallback? onChooseColumns;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('users-directory-surface'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _DirectoryToolbar(
        palette: palette,
        data: data,
        compact: compact,
        searchController: searchController,
        searchFocus: searchFocus,
        visibleColumnCount: columns.length,
        onSearchChanged: onSearchChanged,
        onSearchSubmitted: onSearchSubmitted,
        onClearSearch: onClearSearch,
        onPeriodChanged: onPeriodChanged,
        onGroupChanged: onGroupChanged,
        onChooseColumns: onChooseColumns,
        onRefresh: onRefresh,
      ),
      if (data.loading || data.loadingMore || data.updatingColumns)
        const LinearProgressIndicator(
          key: ValueKey('users-directory-progress'),
          minHeight: 2,
        ),
      Expanded(
        child: KeyedSubtree(
          key: const ValueKey('users-table'),
          child: _TableBody(
            palette: palette,
            data: data,
            columns: columns,
            siteUrl: siteUrl,
            horizontal: horizontal,
            identityVertical: identityVertical,
            metricsVertical: metricsVertical,
            rowHeight: rowHeight,
            headerHeight: headerHeight,
            metricWidth: metricWidth,
            hoveredId: hoveredId,
            onHover: onHover,
            onSort: onSort,
          ),
        ),
      ),
    ],
  );
}

class _DirectoryToolbar extends StatelessWidget {
  const _DirectoryToolbar({
    required this.palette,
    required this.data,
    required this.compact,
    required this.searchController,
    required this.searchFocus,
    required this.visibleColumnCount,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onPeriodChanged,
    required this.onGroupChanged,
    required this.onChooseColumns,
    required this.onRefresh,
  });

  final _MatrixPalette palette;
  final UsersPageData data;
  final bool compact;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final int visibleColumnCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;
  final ValueChanged<String?>? onGroupChanged;
  final VoidCallback? onChooseColumns;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controlHeight = DButton.iconOnlyDimensionFor(DButtonSize.small);
    final search = SizedBox(
      height: controlHeight,
      child: TextField(
        key: const ValueKey('users-search'),
        controller: searchController,
        focusNode: searchFocus,
        onChanged: onSearchChanged,
        onSubmitted: onSearchSubmitted,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: theme.shell.content,
          hintText: 'Search people',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: DIcon(
              DIcons.magnifyingGlass,
              size: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          prefixIconConstraints: BoxConstraints(
            minWidth: 37,
            minHeight: controlHeight,
          ),
          suffixIcon: searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClearSearch,
                  icon: DIcon(
                    DIcons.xmark,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          border: _inputBorder(palette),
          enabledBorder: _inputBorder(palette),
          focusedBorder: _inputBorder(palette, focused: true),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PeriodMenu(selected: data.query.period, onChanged: onPeriodChanged),
        const SizedBox(width: 8),
        _GroupMenu(
          groups: data.groupNames,
          selected: data.query.group,
          onChanged: onGroupChanged,
        ),
        const SizedBox(width: 7),
        _ToolbarButton(
          key: const ValueKey('users-columns'),
          onPressed: onChooseColumns,
          icon: DIcons.list,
          label: 'Columns',
          count: visibleColumnCount,
        ),
        const SizedBox(width: 7),
        _ToolbarIconButton(
          key: const ValueKey('users-refresh'),
          tooltip: 'Refresh directory',
          onPressed: onRefresh == null ? null : () => unawaited(onRefresh!()),
          icon: const DIcon(DIcons.arrowsRotate, size: 14),
        ),
      ],
    );

    return Material(
      key: const ValueKey('users-toolbar'),
      color: theme.shell.sidebar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.shell.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: controls,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 12),
                    controls,
                  ],
                ),
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(
    _MatrixPalette palette, {
    bool focused = false,
  }) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(
      color: focused ? palette.accent : palette.line,
      width: focused ? 1.5 : 1,
    ),
  );
}

class _PeriodMenu extends StatelessWidget {
  const _PeriodMenu({required this.selected, required this.onChanged});

  final UserDirectoryPeriod selected;
  final ValueChanged<UserDirectoryPeriod>? onChanged;

  @override
  Widget build(BuildContext context) => ChoiceMenuAnchor<UserDirectoryPeriod>(
    title: 'Activity period',
    showPopoverTitle: false,
    value: selected,
    options: [
      for (final period in UserDirectoryPeriod.values.reversed)
        ChoiceMenuOption(
          value: period,
          title: period.label,
          description: '',
          compact: true,
        ),
    ],
    enabled: onChanged != null,
    onSelected: (period) => onChanged?.call(period),
    builder: (context, openMenu) => _ToolbarButton(
      key: const ValueKey('users-period-filter'),
      onPressed: openMenu,
      icon: DIcons.farClock,
      label: selected.label,
      chevron: true,
    ),
  );
}

const String _allGroups = '__all_groups__';

class _GroupMenu extends StatelessWidget {
  const _GroupMenu({
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  final List<String> groups;
  final String? selected;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final values = <String>{...groups, ?selected}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ChoiceMenuAnchor<String>(
      title: 'Filter by group',
      value: selected ?? _allGroups,
      filterHint: values.length > 8 ? 'Find a group' : null,
      alwaysVisibleValues: const {_allGroups},
      options: [
        const ChoiceMenuOption(
          value: _allGroups,
          title: 'All groups',
          description: 'Show everyone in the directory',
        ),
        for (final group in values)
          ChoiceMenuOption(
            value: group,
            title: group,
            description: 'Only members of $group',
          ),
      ],
      enabled: onChanged != null,
      onSelected: (value) =>
          onChanged?.call(value == _allGroups ? null : value),
      builder: (context, openMenu) => _ToolbarButton(
        key: const ValueKey('users-group-filter'),
        onPressed: openMenu,
        icon: DIcons.users,
        label: selected ?? 'All groups',
        chevron: true,
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.count,
    this.chevron = false,
  });

  final VoidCallback? onPressed;
  final DIconData icon;
  final String label;
  final int? count;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190, minHeight: 40),
      child: DButton(
        onPressed: onPressed,
        size: DButtonSize.small,
        icon: DIcon(icon, size: 14),
        alignment: Alignment.centerLeft,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
            if (chevron) ...[
              const SizedBox(width: 8),
              const DIcon(DIcons.chevronDown, size: 11),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: icon,
    size: DButtonSize.small,
  );
}

class _TableBody extends StatelessWidget {
  const _TableBody({
    required this.palette,
    required this.data,
    required this.columns,
    required this.siteUrl,
    required this.horizontal,
    required this.identityVertical,
    required this.metricsVertical,
    required this.rowHeight,
    required this.headerHeight,
    required this.metricWidth,
    required this.hoveredId,
    required this.onHover,
    required this.onSort,
  });

  final _MatrixPalette palette;
  final UsersPageData data;
  final List<UserDirectoryColumn> columns;
  final String siteUrl;
  final ScrollController horizontal;
  final ScrollController identityVertical;
  final ScrollController metricsVertical;
  final double rowHeight;
  final double headerHeight;
  final double metricWidth;
  final int? hoveredId;
  final ValueChanged<int?> onHover;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    if (!data.loaded && data.items.isEmpty) {
      return _TableState(
        key: const ValueKey('users-loading'),
        palette: palette,
        icon: DIcons.users,
        title: 'Loading users',
        detail: 'Loading the user directory…',
        progress: true,
      );
    }
    if (data.error != null && data.items.isEmpty) {
      return _TableState(
        key: const ValueKey('users-error'),
        palette: palette,
        icon: DIcons.triangleExclamation,
        title: 'Directory unavailable',
        detail: data.error!,
      );
    }
    if (data.items.isEmpty) {
      return _TableState(
        key: const ValueKey('users-empty'),
        palette: palette,
        icon: DIcons.magnifyingGlass,
        title: 'No matching people',
        detail: 'Try a different search, group, or time window.',
      );
    }

    final maxima = <int, double>{};
    for (final column in columns) {
      var maximum = 0.0;
      for (final item in data.items) {
        maximum = math.max(
          maximum,
          item.numericValueFor(column)?.abs().toDouble() ?? 0,
        );
      }
      maxima[column.id] = maximum;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final identityWidth = constraints.maxWidth < 560 ? 220.0 : 258.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: math.min(identityWidth, constraints.maxWidth - 72),
                child: Column(
                  children: [
                    _IdentityHeader(
                      palette: palette,
                      height: headerHeight,
                      ascending:
                          data.query.order == 'username' &&
                          data.query.ascending,
                      sorted: data.query.order == 'username',
                      onSort: () => onSort('username'),
                    ),
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.builder(
                          key: const PageStorageKey('users-identity-scroll'),
                          controller: identityVertical,
                          itemExtent: rowHeight,
                          itemCount: data.items.length,
                          itemBuilder: (context, index) {
                            final item = data.items[index];
                            final currentUser = _sameUsername(
                              item.user.username,
                              data.currentUsername,
                            );
                            return _IdentityRow(
                              key: ValueKey('user-row-${item.user.username}'),
                              palette: palette,
                              item: item,
                              siteUrl: siteUrl,
                              currentUser: currentUser,
                              hovered: hoveredId == item.id,
                              onHover: onHover,
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, metricConstraints) {
                    final resolvedMetricWidth = columns.isEmpty
                        ? metricWidth
                        : math.max(
                            metricWidth,
                            metricConstraints.maxWidth / columns.length,
                          );
                    final contentWidth = math.max(
                      metricConstraints.maxWidth,
                      columns.length * resolvedMetricWidth,
                    );
                    return Scrollbar(
                      controller: horizontal,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: horizontal,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          height: metricConstraints.maxHeight,
                          child: Column(
                            children: [
                              SizedBox(
                                height: headerHeight,
                                child: Row(
                                  children: [
                                    for (final column in columns)
                                      SizedBox(
                                        width: resolvedMetricWidth,
                                        child: _MetricHeader(
                                          palette: palette,
                                          column: column,
                                          sorted:
                                              data.query.order == column.name,
                                          ascending: data.query.ascending,
                                          onSort: () => onSort(column.name),
                                        ),
                                      ),
                                    if (columns.isEmpty)
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            'Choose columns to show metrics',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: palette.faint,
                                                ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Scrollbar(
                                  controller: metricsVertical,
                                  child: ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(scrollbars: false),
                                    child: ListView.builder(
                                      key: const PageStorageKey(
                                        'users-metrics-scroll',
                                      ),
                                      controller: metricsVertical,
                                      itemExtent: rowHeight,
                                      itemCount: data.items.length,
                                      itemBuilder: (context, index) {
                                        final item = data.items[index];
                                        final currentUser = _sameUsername(
                                          item.user.username,
                                          data.currentUsername,
                                        );
                                        return MouseRegion(
                                          onEnter: (_) => onHover(item.id),
                                          onExit: (_) => onHover(null),
                                          child: ColoredBox(
                                            key: ValueKey(
                                              'user-metrics-background-${item.user.username}',
                                            ),
                                            color: _rowColor(
                                              palette,
                                              currentUser: currentUser,
                                              hovered: hoveredId == item.id,
                                            ),
                                            child: Row(
                                              children: [
                                                for (final column in columns)
                                                  SizedBox(
                                                    width: resolvedMetricWidth,
                                                    child: _MetricCell(
                                                      palette: palette,
                                                      item: item,
                                                      column: column,
                                                      maximum:
                                                          maxima[column.id] ??
                                                          0,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
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
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IdentityHeader extends StatelessWidget {
  const _IdentityHeader({
    required this.palette,
    required this.height,
    required this.ascending,
    required this.sorted,
    required this.onSort,
  });

  final _MatrixPalette palette;
  final double height;
  final bool ascending;
  final bool sorted;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: palette.tableHeader,
      border: Border(
        right: BorderSide(color: palette.line),
        bottom: BorderSide(color: palette.line),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: _HeaderButton(
        label: 'User',
        sorted: sorted,
        ascending: ascending,
        palette: palette,
        onPressed: onSort,
        alignment: Alignment.centerLeft,
      ),
    ),
  );
}

class _MetricHeader extends StatelessWidget {
  const _MetricHeader({
    required this.palette,
    required this.column,
    required this.sorted,
    required this.ascending,
    required this.onSort,
  });

  final _MatrixPalette palette;
  final UserDirectoryColumn column;
  final bool sorted;
  final bool ascending;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: palette.tableHeader,
      border: Border(
        right: BorderSide(color: palette.line),
        bottom: BorderSide(color: palette.line),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: _HeaderButton(
        label: column.label,
        sorted: sorted,
        ascending: ascending,
        palette: palette,
        onPressed: onSort,
        alignment: Alignment.centerRight,
      ),
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.sorted,
    required this.ascending,
    required this.palette,
    required this.onPressed,
    required this.alignment,
  });

  final String label;
  final bool sorted;
  final bool ascending;
  final _MatrixPalette palette;
  final VoidCallback onPressed;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      sortKey: OrdinalSortKey(sorted ? 0 : 1),
      button: true,
      label:
          'Sort by $label${sorted ? ', currently ${ascending ? 'ascending' : 'descending'}' : ''}',
      child: InkWell(
        onTap: onPressed,
        child: Align(
          alignment: alignment,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: alignment == Alignment.centerRight
                      ? TextAlign.right
                      : TextAlign.left,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: sorted ? palette.ink : palette.faint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (sorted) ...[
                const SizedBox(width: 4),
                Transform.rotate(
                  angle: ascending ? 0 : math.pi,
                  child: DIcon(DIcons.arrowUp, size: 10, color: palette.green),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    super.key,
    required this.palette,
    required this.item,
    required this.siteUrl,
    required this.currentUser,
    required this.hovered,
    required this.onHover,
  });

  final _MatrixPalette palette;
  final UserDirectoryItem item;
  final String siteUrl;
  final bool currentUser;
  final bool hovered;
  final ValueChanged<int?> onHover;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => onHover(item.id),
    onExit: (_) => onHover(null),
    child: Container(
      key: ValueKey('user-identity-background-${item.user.username}'),
      decoration: BoxDecoration(
        color: _rowColor(palette, currentUser: currentUser, hovered: hovered),
        border: Border(
          right: BorderSide(color: palette.line),
          bottom: BorderSide(color: palette.rowLine),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: UserCardTarget(
                username: item.user.username,
                siteUrl: siteUrl.isEmpty ? null : siteUrl,
                child: Row(
                  children: [
                    ClipRRect(
                      key: ValueKey('user-avatar-${item.user.username}'),
                      borderRadius: Theme.of(
                        context,
                      ).avatars.borderRadiusFor(32),
                      child: AvatarImage(
                        url: item.user.avatarUrl,
                        size: 32,
                        fallback: _AvatarFallback(
                          palette: palette,
                          user: item.user,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  item.user.username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: palette.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              if (item.user.primaryGroupName
                                  case final group?) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.green.withValues(alpha: .1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    group,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: palette.green,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.user.name ?? item.user.title ?? 'Member',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: palette.faint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.palette, required this.user});

  final _MatrixPalette palette;
  final UserDirectoryUser user;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    color: palette.avatarFor(user.id),
    child: Text(
      _initials(user),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: palette.dark,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.palette,
    required this.item,
    required this.column,
    required this.maximum,
  });

  final _MatrixPalette palette;
  final UserDirectoryItem item;
  final UserDirectoryColumn column;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    final numeric = item.numericValueFor(column);
    final intensity = maximum <= 0 || numeric == null
        ? 0.0
        : (numeric.abs() / maximum).clamp(0.0, 1.0).toDouble();
    final userField = column.type == UserDirectoryColumnType.userField;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: palette.rowLine),
          bottom: BorderSide(color: palette.rowLine),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (intensity > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: math.max(.06, intensity),
                heightFactor: .64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(
                      alpha: .12 + intensity * .18,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          Align(
            alignment: userField ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              _formatValue(item.valueFor(column), column),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: userField ? TextAlign.left : TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.ink,
                fontWeight: numeric == null ? FontWeight.w400 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableState extends StatelessWidget {
  const _TableState({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.detail,
    this.progress = false,
  });

  final _MatrixPalette palette;
  final DIconData icon;
  final String title;
  final String detail;
  final bool progress;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: DIcon(icon, size: 18, color: palette.green),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.muted),
          ),
          if (progress) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: 110,
              child: LinearProgressIndicator(
                color: palette.green,
                backgroundColor: palette.line,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

@immutable
final class _MatrixPalette {
  const _MatrixPalette({
    required this.surface,
    required this.tableHeader,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.rowLine,
    required this.dark,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.green,
    required this.hover,
    required this.currentUser,
    required this.avatarBackground,
  });

  factory _MatrixPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _MatrixPalette(
      surface: theme.shell.content,
      tableHeader: theme.shell.sidebar,
      ink: colors.onSurface,
      muted: colors.onSurfaceVariant,
      faint: colors.onSurfaceVariant.withValues(alpha: .72),
      line: theme.shell.divider,
      rowLine: theme.shell.divider.withValues(alpha: .72),
      dark: colors.onSecondaryContainer,
      accent: colors.primary,
      accentInk: colors.onPrimaryContainer,
      accentSoft: colors.primaryContainer,
      green: colors.primary,
      hover: theme.shell.hover,
      currentUser: colors.tertiaryContainer,
      avatarBackground: colors.secondaryContainer,
    );
  }

  final Color surface;
  final Color tableHeader;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;
  final Color rowLine;
  final Color dark;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color green;
  final Color hover;
  final Color currentUser;
  final Color avatarBackground;

  Color avatarFor(int _) => avatarBackground;
}

Color _rowColor(
  _MatrixPalette palette, {
  required bool currentUser,
  required bool hovered,
}) {
  if (hovered) return palette.hover;
  if (currentUser) return palette.currentUser;
  return palette.surface;
}

bool _sameUsername(String username, String? currentUsername) =>
    currentUsername != null &&
    username.toLowerCase() == currentUsername.toLowerCase();

String _formatValue(Object? value, UserDirectoryColumn column) {
  if (value == null) return '—';
  if (value is List) {
    final joined = value.whereType<Object>().map((item) => '$item').join(' · ');
    return joined.isEmpty ? '—' : joined;
  }
  final numeric = switch (value) {
    final num number when number.isFinite => number,
    final String text => num.tryParse(text),
    _ => null,
  };
  if (numeric == null) return '$value';
  if (column.name == 'time_read') {
    final duration = Duration(seconds: numeric.toInt());
    if (duration.inHours >= 1) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    return '${duration.inMinutes}m';
  }
  return _formatCompact(numeric);
}

String _formatCompact(num value) {
  final absolute = value.abs();
  if (absolute >= 1000000) {
    return '${_trimDecimal(value / 1000000)}m';
  }
  if (absolute >= 1000) return '${_trimDecimal(value / 1000)}k';
  return value is int || value == value.roundToDouble()
      ? value.toInt().toString()
      : _trimDecimal(value.toDouble());
}

String _trimDecimal(num value) => value
    .toStringAsFixed(value.abs() >= 10 ? 0 : 1)
    .replaceFirst(RegExp(r'\.0$'), '');

String _initials(UserDirectoryUser user) {
  final words = (user.name ?? user.username)
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList();
  if (words.isEmpty) return '?';
  return words.map((word) => word.characters.first).join().toUpperCase();
}
