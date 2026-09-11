import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/user_directory_column_width_store.dart';
import '../models/user_directory.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../utils/pagination.dart';
import 'avatar_image.dart';
import 'shell_scope.dart';
import 'user_card.dart';
import 'user_directory_controller.dart';

const String _identityColumnWidthKey = 'identity';

String _metricColumnWidthKey(UserDirectoryColumn column) =>
    'metric.${column.type.name}.${column.id}';

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
    this.columnWidthStore = const UserDirectoryColumnWidthStore(),
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
  final UserDirectoryColumnWidthStore columnWidthStore;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  Timer? _searchDebounce;
  int _ownerGeneration = 0;
  Set<int>? _visibleColumnIds;
  Map<int, double> _columnMaxima = const {};
  bool _loadMoreCheckScheduled = false;
  bool _loadMoreRequested = false;
  Map<String, double> _columnWidths = const {};
  bool _columnWidthsDirty = false;
  int _columnWidthRestoreGeneration = 0;
  int _columnWidthInteractionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.data.query.search);
    _vertical.addListener(_scheduleLoadMoreCheck);
    _deriveColumnMaxima();
    _restoreColumnWidths();
  }

  @override
  void didUpdateWidget(UsersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged =
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.data.currentUsername != widget.data.currentUsername;
    if (ownerChanged) {
      _ownerGeneration++;
      _searchDebounce?.cancel();
      _visibleColumnIds = null;
    }
    if (ownerChanged ||
        oldWidget.data.query != widget.data.query ||
        !listEquals(oldWidget.data.items, widget.data.items) ||
        !listEquals(oldWidget.data.columns, widget.data.columns)) {
      _deriveColumnMaxima();
    }
    if (oldWidget.siteUrl != widget.siteUrl ||
        !identical(oldWidget.columnWidthStore, widget.columnWidthStore)) {
      _flushColumnWidths(
        siteUrl: oldWidget.siteUrl,
        store: oldWidget.columnWidthStore,
      );
      _columnWidths = const {};
      _columnWidthsDirty = false;
      _restoreColumnWidths();
    }
    if (ownerChanged ||
        (!_searchFocus.hasFocus &&
            widget.data.query.search != _searchController.text)) {
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
    if (ownerChanged ||
        oldWidget.data.items.length != widget.data.items.length ||
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
    _flushColumnWidths();
    _searchController.dispose();
    _searchFocus.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _deriveColumnMaxima() {
    // Rows and columns are immutable snapshots. Retain only this page's
    // configured columns, including hidden ones so the picker needs no scan.
    _columnMaxima = {
      for (final column in widget.data.columns)
        column.id: widget.data.items.fold<double>(
          0,
          (maximum, item) => math.max(
            maximum,
            item.numericValueFor(column)?.abs().toDouble() ?? 0,
          ),
        ),
    };
  }

  void _restoreColumnWidths() {
    final restoreGeneration = ++_columnWidthRestoreGeneration;
    final interactionGeneration = _columnWidthInteractionGeneration;
    final siteUrl = widget.siteUrl;
    final store = widget.columnWidthStore;
    unawaited(() async {
      final restored = await store.read(siteUrl: siteUrl);
      if (!mounted ||
          restoreGeneration != _columnWidthRestoreGeneration ||
          siteUrl != widget.siteUrl ||
          !identical(store, widget.columnWidthStore)) {
        return;
      }
      final interacted =
          interactionGeneration != _columnWidthInteractionGeneration;
      final resolved = interacted
          ? {...restored.widths, ..._columnWidths}
          : restored.widths;
      setState(() => _columnWidths = Map.unmodifiable(resolved));
      if (interacted &&
          !_columnWidthsDirty &&
          !mapEquals(resolved, restored.widths)) {
        unawaited(
          store.write(
            siteUrl: siteUrl,
            widths: UserDirectoryColumnWidths(resolved),
          ),
        );
      }
    }());
  }

  void _beginColumnResize() {
    _columnWidthInteractionGeneration++;
  }

  void _resizeColumns(Map<String, double> widths) {
    if (mapEquals(_columnWidths, widths)) return;
    _columnWidthInteractionGeneration++;
    setState(() {
      _columnWidths = Map.unmodifiable(widths);
      _columnWidthsDirty = true;
    });
  }

  void _finishColumnResize() {
    _flushColumnWidths();
  }

  void _flushColumnWidths({
    String? siteUrl,
    UserDirectoryColumnWidthStore? store,
  }) {
    if (!_columnWidthsDirty) return;
    final snapshot = UserDirectoryColumnWidths(_columnWidths);
    _columnWidthsDirty = false;
    unawaited(
      (store ?? widget.columnWidthStore).write(
        siteUrl: siteUrl ?? widget.siteUrl,
        widths: snapshot,
      ),
    );
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
    final position = _vertical.hasClients ? _vertical.position : null;
    if (position == null ||
        position.extentAfter > paginationPrefetchDistance(position)) {
      return;
    }
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
    final generation = _ownerGeneration;
    final columns = widget.data.columns;
    final draft = Set<int>.from(
      _visibleColumnIds ?? columns.map((column) => column.id),
    );
    final result = await showDDialog<Set<int>>(
      context: context,
      builder: (dialogContext, dialog) => StatefulBuilder(
        builder: (context, updateDialog) => DDialogContent(
          children: [
            const DDialogHeader(
              children: [DDialogTitle(child: Text('Visible columns'))],
            ),
            DDialogScrollArea(
              child: Column(
                children: [
                  for (final column in columns)
                    DCheckbox(
                      key: ValueKey('users-column-${column.id}'),
                      value: draft.contains(column.id),
                      title: Text(column.label),
                      onChanged: (visible) => updateDialog(() {
                        visible == true
                            ? draft.add(column.id)
                            : draft.remove(column.id);
                      }),
                    ),
                ],
              ),
            ),
            DDialogFooter(
              children: [
                DButton(
                  onPressed: () => updateDialog(() {
                    draft
                      ..clear()
                      ..addAll(columns.map((column) => column.id));
                  }),
                  label: const Text('Show all'),
                  variant: DButtonVariant.ghost,
                ),
                DButton(
                  onPressed: () => dialog.close(draft),
                  label: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (!mounted || generation != _ownerGeneration || result == null) return;
    setState(() => _visibleColumnIds = result);
  }

  Future<void> _manageColumns() async {
    final generation = _ownerGeneration;
    final save = widget.onManageColumns;
    if (save == null) return;
    var draft = [...widget.data.availableColumns]
      ..sort((a, b) => a.position.compareTo(b.position));
    final result = await showDDialog<List<UserDirectoryColumn>>(
      context: context,
      builder: (dialogContext, dialog) => StatefulBuilder(
        builder: (context, updateDialog) {
          void move(int from, int to) => updateDialog(() {
            final moved = draft.removeAt(from);
            draft.insert(to, moved);
            draft = [
              for (final (index, column) in draft.indexed)
                column.copyWith(position: index + 1),
            ];
          });
          return DDialogContent(
            key: const ValueKey('users-manage-columns-dialog'),
            maxWidth: 608,
            children: [
              const DDialogHeader(
                children: [DDialogTitle(child: Text('Directory columns'))],
              ),
              DDialogScrollArea(
                key: const ValueKey('users-manage-columns-content'),
                maxHeightFactor: .6,
                child: Column(
                  key: const ValueKey('users-manage-columns-list'),
                  children: [
                    for (var index = 0; index < draft.length; index++) ...[
                      if (index > 0) const DSeparator(space: 1),
                      Row(
                        children: [
                          Expanded(
                            child: DCheckbox(
                              key: ValueKey(
                                'users-manage-column-${draft[index].id}',
                              ),
                              value: draft[index].enabled,
                              title: Text(
                                draft[index].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(switch (draft[index].type) {
                                UserDirectoryColumnType.automatic => 'Activity',
                                UserDirectoryColumnType.userField =>
                                  'User field',
                                UserDirectoryColumnType.plugin => 'Plugin',
                              }),
                              onChanged: (enabled) => updateDialog(() {
                                draft[index] = draft[index].copyWith(
                                  enabled: enabled ?? false,
                                );
                              }),
                            ),
                          ),
                          DButton.iconOnly(
                            key: ValueKey('users-column-up-${draft[index].id}'),
                            tooltip: 'Move ${draft[index].label} up',
                            onPressed: index == 0
                                ? null
                                : () => move(index, index - 1),
                            size: DButtonSize.small,
                            variant: DButtonVariant.ghost,
                            icon: const DIcon(DIcons.arrowUp),
                          ),
                          DButton.iconOnly(
                            key: ValueKey(
                              'users-column-down-${draft[index].id}',
                            ),
                            tooltip: 'Move ${draft[index].label} down',
                            onPressed: index == draft.length - 1
                                ? null
                                : () => move(index, index + 1),
                            size: DButtonSize.small,
                            variant: DButtonVariant.ghost,
                            icon: Transform.rotate(
                              angle: math.pi,
                              child: const DIcon(DIcons.arrowUp),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              DDialogFooter(
                children: [
                  DButton(
                    onPressed: () => dialog.close(),
                    label: const Text('Cancel'),
                    variant: DButtonVariant.ghost,
                  ),
                  DButton(
                    key: const ValueKey('users-save-columns'),
                    onPressed: draft.any((column) => column.enabled)
                        ? () => dialog.close(draft)
                        : null,
                    label: const Text('Save changes'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    if (!mounted ||
        generation != _ownerGeneration ||
        result == null ||
        !widget.data.canManageColumns ||
        widget.onManageColumns == null) {
      return;
    }
    final saved = await save(List.unmodifiable(result));
    if (!mounted || generation != _ownerGeneration || saved) return;
    DToast.show(
      context,
      "Couldn't update directory columns.",
      type: DToastType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _DirectoryPalette.of(context);
    final columns = _visibleColumns;
    _scheduleLoadMoreCheck();
    return ColoredBox(
      key: const ValueKey('users-page'),
      color: palette.surface,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          key: const ValueKey('users-directory-surface'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DirectoryToolbar(
              palette: palette,
              data: widget.data,
              compact:
                  constraints.maxWidth <
                  720 * MediaQuery.textScalerOf(context).scale(14) / 14,
              searchController: _searchController,
              searchFocus: _searchFocus,
              visibleColumnCount: columns.length,
              onSearchChanged: _search,
              onSearchSubmitted: _submitSearch,
              onClearSearch: () {
                _searchController.clear();
                _submitSearch('');
                setState(() {});
              },
              onPeriodChanged: widget.onPeriodChanged,
              onGroupChanged: widget.onGroupChanged,
              onChooseColumns: widget.data.updatingColumns
                  ? null
                  : _chooseColumns,
              onRefresh: widget.onRefresh,
            ),
            Expanded(
              child: _DirectoryTable(
                key: const ValueKey('users-table'),
                palette: palette,
                data: widget.data,
                columns: columns,
                siteUrl: widget.siteUrl,
                horizontal: _horizontal,
                vertical: _vertical,
                columnWidths: _columnWidths,
                columnMaxima: _columnMaxima,
                onSort: widget.onSortChanged,
                onColumnResizeStart: _beginColumnResize,
                onColumnWidthsChanged: _resizeColumns,
                onColumnResizeEnd: _finishColumnResize,
              ),
            ),
          ],
        ),
      ),
    );
  }
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

  final _DirectoryPalette palette;
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
    final search = DInput(
      key: const ValueKey('users-search'),
      controller: searchController,
      focusNode: searchFocus,
      semanticLabel: 'Search people',
      hintText: 'Search people',
      onChanged: onSearchChanged,
      onSubmitted: onSearchSubmitted,
      textInputAction: TextInputAction.search,
      prefix: const DIcon(DIcons.magnifyingGlass, size: 16),
      suffix: searchController.text.isEmpty
          ? null
          : DButton.iconOnly(
              tooltip: 'Clear search',
              onPressed: onClearSearch,
              variant: DButtonVariant.ghost,
              size: DButtonSize.small,
              icon: const DIcon(DIcons.xmark, size: 16),
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
          loading: data.loading,
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
}

class _PeriodMenu extends StatelessWidget {
  const _PeriodMenu({required this.selected, required this.onChanged});

  final UserDirectoryPeriod selected;
  final ValueChanged<UserDirectoryPeriod>? onChanged;

  @override
  Widget build(BuildContext context) => DSelect<UserDirectoryPeriod>(
    key: const ValueKey('users-period-filter'),
    value: selected,
    semanticLabel: 'Activity period',
    enabled: onChanged != null,
    onChanged: (value) {
      if (value != null) onChanged?.call(value);
    },
    entries: [
      for (final period in UserDirectoryPeriod.values.reversed)
        DSelectItem(
          value: period,
          textValue: period.label,
          child: Text(period.label),
        ),
    ],
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: DSelect<String>(
        key: const ValueKey('users-group-filter'),
        value: selected ?? _allGroups,
        semanticLabel: 'Filter by group',
        enabled: onChanged != null,
        onChanged: (value) =>
            onChanged?.call(value == _allGroups ? null : value),
        entries: [
          const DSelectItem(
            value: _allGroups,
            textValue: 'All groups',
            child: Text('All groups'),
          ),
          for (final group in values)
            DSelectItem(value: group, textValue: group, child: Text(group)),
        ],
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
  });

  final VoidCallback? onPressed;
  final DIconData icon;
  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: DButton(
        onPressed: onPressed,
        size: DButtonSize.small,
        variant: DButtonVariant.outline,
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
              DBadge(variant: DBadgeVariant.secondary, child: Text('$count')),
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
    this.loading = false,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;
  final bool loading;

  @override
  Widget build(BuildContext context) => DButton.iconOnly(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: icon,
    loading: loading,
    variant: DButtonVariant.outline,
    size: DButtonSize.small,
  );
}

class _DirectoryTable extends StatelessWidget {
  const _DirectoryTable({
    super.key,
    required this.palette,
    required this.data,
    required this.columns,
    required this.siteUrl,
    required this.horizontal,
    required this.vertical,
    required this.columnWidths,
    required this.columnMaxima,
    required this.onSort,
    required this.onColumnResizeStart,
    required this.onColumnWidthsChanged,
    required this.onColumnResizeEnd,
  });

  final _DirectoryPalette palette;
  final UsersPageData data;
  final List<UserDirectoryColumn> columns;
  final String siteUrl;
  final ScrollController horizontal;
  final ScrollController vertical;
  final Map<String, double> columnWidths;
  final Map<int, double> columnMaxima;
  final void Function(String order, bool ascending)? onSort;
  final VoidCallback onColumnResizeStart;
  final ValueChanged<Map<String, double>> onColumnWidthsChanged;
  final VoidCallback onColumnResizeEnd;

  @override
  Widget build(BuildContext context) {
    if (data.error != null && data.items.isEmpty) {
      return _TableState(
        key: const ValueKey('users-error'),
        palette: palette,
        icon: DIcons.triangleExclamation,
        title: 'Directory unavailable',
        detail: data.error!,
      );
    }
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
    if (data.items.isEmpty) {
      return _TableState(
        key: const ValueKey('users-empty'),
        palette: palette,
        icon: DIcons.magnifyingGlass,
        title: 'No matching people',
        detail: 'Try a different search, group, or time window.',
      );
    }

    final orderById = {
      _identityColumnWidthKey: 'username',
      for (final column in columns) _metricColumnWidthKey(column): column.name,
    };
    final sortedId = orderById.entries
        .where((entry) => entry.value == data.query.order)
        .firstOrNull
        ?.key;
    return LayoutBuilder(
      builder: (context, constraints) {
        final identityWidth = (columnWidths[_identityColumnWidthKey] ?? 258)
            .clamp(180, 520)
            .toDouble();
        final automaticCount = columns
            .where(
              (column) =>
                  !columnWidths.containsKey(_metricColumnWidthKey(column)),
            )
            .length;
        final explicitWidth = columns.fold<double>(
          identityWidth,
          (total, column) =>
              total +
              (columnWidths[_metricColumnWidthKey(column)]?.clamp(88, 4096) ??
                  0),
        );
        final metricWidth = automaticCount == 0
            ? 160.0
            : math.max(
                160.0,
                (constraints.maxWidth - explicitWidth) / automaticCount,
              );
        return DDataTable<UserDirectoryItem>(
          key: ValueKey((siteUrl, data.currentUsername, data.query)),
          semanticLabel: 'Users',
          data: data.items,
          rowId: (item) => item.id,
          operationMode: DDataTableOperationMode.manual,
          rowCount: data.totalRows,
          virtualized: true,
          scrollController: horizontal,
          verticalScrollController: vertical,
          columnWidths: columnWidths,
          onColumnWidthsChanged: onColumnWidthsChanged,
          onColumnResizeStart: onColumnResizeStart,
          onColumnResizeEnd: onColumnResizeEnd,
          state: DDataTableState(
            sort: sortedId == null
                ? null
                : DDataTableSort(
                    columnId: sortedId,
                    direction: data.query.ascending
                        ? DDataTableSortDirection.ascending
                        : DDataTableSortDirection.descending,
                  ),
          ),
          onStateChanged: (next) {
            final sort = next.sort;
            final order = sort == null ? null : orderById[sort.columnId];
            if (sort != null &&
                order != null &&
                (order != data.query.order ||
                    (sort.direction == DDataTableSortDirection.ascending) !=
                        data.query.ascending)) {
              onSort?.call(
                order,
                sort.direction == DDataTableSortDirection.ascending,
              );
            }
          },
          columns: [
            DDataTableColumn(
              id: _identityColumnWidthKey,
              label: 'User',
              hideable: false,
              resizable: true,
              width: const FixedColumnWidth(258),
              minWidth: 180,
              maxWidth: 520,
              compare: onSort == null
                  ? null
                  : (a, b) => a.user.username.compareTo(b.user.username),
              headerBuilder: _header,
              cellBuilder: (context, cell) => _IdentityCell(
                key: ValueKey('user-row-${cell.row.user.username}'),
                item: cell.row,
                siteUrl: siteUrl,
                currentUser: _sameUsername(
                  cell.row.user.username,
                  data.currentUsername,
                ),
              ),
            ),
            for (final column in columns)
              DDataTableColumn(
                id: _metricColumnWidthKey(column),
                label: column.label,
                hideable: false,
                resizable: true,
                width: FixedColumnWidth(metricWidth),
                minWidth: 88,
                maxWidth: 4096,
                // Manual mode delegates ordering to the server; no local sort runs.
                compare: onSort == null
                    ? null
                    : (a, b) => (a.numericValueFor(column) ?? 0).compareTo(
                        b.numericValueFor(column) ?? 0,
                      ),
                headerBuilder: _header,
                alignment: column.type == UserDirectoryColumnType.userField
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                cellBuilder: (context, cell) => _MetricCell(
                  key: ValueKey(
                    'user-metric-${cell.row.user.username}-${column.id}',
                  ),
                  item: cell.row,
                  column: column,
                  maximum: columnMaxima[column.id] ?? 0,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _header(
    BuildContext context,
    DDataTableHeaderContext<UserDirectoryItem> header,
  ) => DDataTableColumnHeader(
    title: header.column.label,
    sortDirection: header.sortDirection,
    onSortChanged: header.onSortChanged,
  );
}

class _IdentityCell extends StatelessWidget {
  const _IdentityCell({
    super.key,
    required this.item,
    required this.siteUrl,
    required this.currentUser,
  });
  final UserDirectoryItem item;
  final String siteUrl;
  final bool currentUser;

  @override
  Widget build(BuildContext context) => UserCardTarget(
    username: item.user.username,
    siteUrl: siteUrl.isEmpty ? null : siteUrl,
    child: Row(
      children: [
        DAvatar.frame(
          key: ValueKey('user-avatar-${item.user.username}'),
          borderRadius: Theme.of(context).avatars.borderRadiusFor(32),
          child: AvatarImage(
            url: item.user.avatarUrl,
            size: 32,
            fallback: SizedBox.square(
              dimension: 32,
              child: DAvatarFallback(child: Text(_initials(item.user))),
            ),
          ),
        ),
        const SizedBox(width: DSpacing.sm),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.user.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                item.user.name ?? item.user.title ?? 'Member',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: DTokens.of(context).mutedForeground),
              ),
              if (item.user.primaryGroupName != null || currentUser)
                Wrap(
                  spacing: DSpacing.xs,
                  children: [
                    if (item.user.primaryGroupName case final group?)
                      DBadge(
                        variant: DBadgeVariant.secondary,
                        child: Text(group),
                      ),
                    if (currentUser)
                      const DBadge(
                        variant: DBadgeVariant.outline,
                        child: Text('You'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    super.key,
    required this.item,
    required this.column,
    required this.maximum,
  });
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
    return Stack(
      alignment: userField
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      children: [
        if (intensity > 0)
          Positioned.fill(
            child: Center(
              child: DChartBar(
                fraction: math.max(.06, intensity),
                height: 24,
                color: DTokens.of(
                  context,
                ).primary.withValues(alpha: .12 + intensity * .18),
              ),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Align(
            alignment: userField
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            child: Text(
              _formatValue(item.valueFor(column), column, numeric),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: userField ? TextAlign.start : TextAlign.end,
              style: TextStyle(
                fontWeight: numeric == null ? FontWeight.w400 : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
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

  final _DirectoryPalette palette;
  final DIconData icon;
  final String title;
  final String detail;
  final bool progress;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
              DEmptyTitle(title),
              DEmptyDescription(detail),
            ],
          ),
          if (progress)
            DEmptyContent(
              children: [
                SizedBox(
                  width: 110,
                  child: DProgress(
                    semanticsLabel: 'Loading users',
                    track: DProgressTrack(
                      color: palette.line,
                      child: DProgressIndicator(color: palette.green),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

@immutable
final class _DirectoryPalette {
  const _DirectoryPalette({
    required this.surface,
    required this.line,
    required this.green,
  });
  factory _DirectoryPalette.of(BuildContext context) => _DirectoryPalette(
    surface: DTokens.of(context).background,
    line: DTokens.of(context).border,
    green: DTokens.of(context).primary,
  );
  final Color surface;
  final Color line;
  final Color green;
}

bool _sameUsername(String username, String? currentUsername) =>
    currentUsername != null &&
    username.toLowerCase() == currentUsername.toLowerCase();

String _formatValue(Object? value, UserDirectoryColumn column, num? numeric) {
  if (value == null) return '—';
  if (value is List) {
    final joined = value.whereType<Object>().map((item) => '$item').join(' · ');
    return joined.isEmpty ? '—' : joined;
  }
  if (numeric == null) return '$value';
  if (column.name == 'time_read') {
    // Duration stores microseconds in a native signed 64-bit integer.
    const maximumSeconds = 0x7fffffffffffffff ~/ Duration.microsecondsPerSecond;
    if (numeric < -maximumSeconds || numeric > maximumSeconds) return '$value';
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
