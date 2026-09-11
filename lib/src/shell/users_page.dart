import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/user_directory_column_width_store.dart';
import '../models/user_directory.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../utils/pagination.dart';
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
  late String _searchText;
  Map<String, double> _columnMaxima = const {};
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  Timer? _searchDebounce;
  int _ownerGeneration = 0;
  Set<String> _hiddenColumnIds = {};
  bool _loadMoreCheckScheduled = false;
  bool _loadMoreRequested = false;
  Map<String, double> _columnWidths = const {};
  bool _columnWidthsDirty = false;
  int _columnWidthRestoreGeneration = 0;
  int _columnWidthInteractionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _searchText = widget.data.query.search;
    _deriveColumnMaxima();
    _vertical.addListener(_scheduleLoadMoreCheck);
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
      _hiddenColumnIds = {};
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
        oldWidget.data.query.search != widget.data.query.search) {
      _searchText = widget.data.query.search;
    }
    if (!listEquals(oldWidget.data.items, widget.data.items) ||
        !listEquals(oldWidget.data.columns, widget.data.columns)) {
      _deriveColumnMaxima();
    }
    final columnIds = {
      'name',
      for (final column in widget.data.columns) _metricColumnWidthKey(column),
    };
    _hiddenColumnIds.removeWhere((id) => !columnIds.contains(id));
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
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _deriveColumnMaxima() {
    _columnMaxima = {
      for (final column in widget.data.columns)
        _metricColumnWidthKey(column): widget.data.items.fold<double>(
          0,
          (maximum, item) => math.max(
            maximum,
            item.numericValueFor(column)?.abs().toDouble() ?? 0,
          ),
        ),
    };
  }

  Widget _metricCell(
    BuildContext context,
    UserDirectoryItem item,
    UserDirectoryColumn column,
  ) {
    final numeric = item.numericValueFor(column);
    final maximum = _columnMaxima[_metricColumnWidthKey(column)] ?? 0;
    final fraction = maximum > 0 && numeric != null
        ? (numeric.abs() / maximum).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return Stack(
      key: ValueKey('user-metric-${item.user.username}-${column.id}'),
      children: [
        if (fraction > 0)
          Positioned.fill(
            child: ExcludeSemantics(
              child: DChartBar(
                fraction: fraction,
                color: DTokens.of(context).primary.withValues(alpha: 0.2),
              ),
            ),
          ),
        Align(
          alignment: column.type == UserDirectoryColumnType.userField
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
          child: Text(_formatValue(item.valueFor(column), column, numeric)),
        ),
      ],
    );
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
    setState(() => _searchText = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => widget.onSearchChanged?.call(value.trim()),
    );
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

  List<DDataTableColumn<UserDirectoryItem>> _columns(double metricWidth) => [
    DDataTableColumn(
      id: _identityColumnWidthKey,
      label: 'User',
      hideable: false,
      resizable: true,
      width: const FixedColumnWidth(180),
      minWidth: 120,
      maxWidth: 520,
      compare: widget.onSortChanged == null
          ? null
          : (a, b) => a.user.username.compareTo(b.user.username),
      headerBuilder: _header,
      cellBuilder: (context, cell) => UserCardTarget(
        key: ValueKey('user-row-${cell.row.user.username}'),
        username: cell.row.user.username,
        siteUrl: widget.siteUrl.isEmpty ? null : widget.siteUrl,
        child: Text(cell.row.user.username),
      ),
    ),
    DDataTableColumn(
      id: 'name',
      label: 'Name',
      resizable: true,
      width: const FixedColumnWidth(200),
      minWidth: 120,
      maxWidth: 800,
      cellBuilder: (context, cell) => Text(cell.row.user.name ?? '—'),
    ),
    for (final column in widget.data.columns)
      DDataTableColumn(
        id: _metricColumnWidthKey(column),
        label: column.label,
        resizable: true,
        width: FixedColumnWidth(metricWidth),
        minWidth: 88,
        maxWidth: 4096,
        // Manual mode delegates ordering to the server.
        compare: widget.onSortChanged == null
            ? null
            : (a, b) => (a.numericValueFor(column) ?? 0).compareTo(
                b.numericValueFor(column) ?? 0,
              ),
        headerBuilder: _header,
        alignment: column.type == UserDirectoryColumnType.userField
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        cellBuilder: (context, cell) => _metricCell(context, cell.row, column),
      ),
  ];

  Widget _header(
    BuildContext context,
    DDataTableHeaderContext<UserDirectoryItem> header,
  ) => DDataTableColumnHeader(
    title: header.column.label,
    sortDirection: header.sortDirection,
    onSortChanged: header.onSortChanged,
    onHide: header.onVisibilityChanged == null
        ? null
        : () => header.onVisibilityChanged!(false),
  );

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    _scheduleLoadMoreCheck();
    final orderById = {
      _identityColumnWidthKey: 'username',
      for (final column in data.columns)
        _metricColumnWidthKey(column): column.name,
    };
    final sortedId = orderById.entries
        .where((entry) => entry.value == data.query.order)
        .firstOrNull
        ?.key;
    return ColoredBox(
      key: const ValueKey('users-page'),
      color: DTokens.of(context).background,
      child: Padding(
        padding: const EdgeInsets.all(DSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visibleMetrics = data.columns.where(
              (column) =>
                  !_hiddenColumnIds.contains(_metricColumnWidthKey(column)),
            );
            final fixedWidth =
                (_columnWidths[_identityColumnWidthKey] ?? 180).clamp(
                  120,
                  520,
                ) +
                (_hiddenColumnIds.contains('name')
                    ? 0
                    : (_columnWidths['name'] ?? 200).clamp(120, 800));
            final explicitWidth = visibleMetrics.fold<double>(
              fixedWidth.toDouble(),
              (total, column) =>
                  total +
                  (_columnWidths[_metricColumnWidthKey(column)]?.clamp(
                        88,
                        4096,
                      ) ??
                      0),
            );
            final automaticCount = visibleMetrics
                .where(
                  (column) =>
                      !_columnWidths.containsKey(_metricColumnWidthKey(column)),
                )
                .length;
            final metricWidth = automaticCount == 0
                ? 160.0
                : math.max(
                    160.0,
                    (constraints.maxWidth - explicitWidth) / automaticCount,
                  );
            final columns = _columns(metricWidth);
            return Column(
              key: const ValueKey('users-directory-surface'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  key: const ValueKey('users-toolbar'),
                  spacing: DSpacing.sm,
                  runSpacing: DSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: math.min(384, constraints.maxWidth),
                      child: DDataTableFilterField(
                        key: const ValueKey('users-search'),
                        value: _searchText,
                        hintText: 'Filter users…',
                        onChanged: _search,
                      ),
                    ),
                    DSelect<UserDirectoryPeriod>(
                      key: const ValueKey('users-period-filter'),
                      value: data.query.period,
                      semanticLabel: 'Activity period',
                      enabled: widget.onPeriodChanged != null,
                      onChanged: (value) {
                        if (value != null) widget.onPeriodChanged?.call(value);
                      },
                      entries: [
                        for (final period
                            in UserDirectoryPeriod.values.reversed)
                          DSelectItem(
                            value: period,
                            textValue: period.label,
                            child: Text(period.label),
                          ),
                      ],
                    ),
                    DSelect<String>(
                      key: const ValueKey('users-group-filter'),
                      value: data.query.group ?? '__all_groups__',
                      semanticLabel: 'Filter by group',
                      enabled: widget.onGroupChanged != null,
                      onChanged: (value) => widget.onGroupChanged?.call(
                        value == '__all_groups__' ? null : value,
                      ),
                      entries: [
                        const DSelectItem(
                          value: '__all_groups__',
                          textValue: 'All groups',
                          child: Text('All groups'),
                        ),
                        for (final group
                            in (<String>{
                              ...data.groupNames,
                              ?data.query.group,
                            }.toList()..sort(
                              (a, b) =>
                                  a.toLowerCase().compareTo(b.toLowerCase()),
                            )))
                          DSelectItem(
                            value: group,
                            textValue: group,
                            child: Text(group),
                          ),
                      ],
                    ),
                    DDataTableColumnToggle<UserDirectoryItem>(
                      key: const ValueKey('users-columns'),
                      columns: columns,
                      hiddenColumnIds: _hiddenColumnIds,
                      onChanged: (hidden) =>
                          setState(() => _hiddenColumnIds = Set.of(hidden)),
                    ),
                    if (data.canManageColumns &&
                        data.availableColumns.isNotEmpty &&
                        widget.onManageColumns != null)
                      DButton(
                        key: const ValueKey('users-manage-columns'),
                        variant: DButtonVariant.outline,
                        label: const Text('Manage columns'),
                        onPressed: data.updatingColumns ? null : _manageColumns,
                      ),
                    DButton.iconOnly(
                      key: const ValueKey('users-refresh'),
                      tooltip: 'Refresh directory',
                      variant: DButtonVariant.outline,
                      loading: data.loading,
                      icon: const DIcon(DIcons.arrowsRotate),
                      onPressed: widget.onRefresh == null
                          ? null
                          : () => unawaited(widget.onRefresh!()),
                    ),
                  ],
                ),
                const SizedBox(height: DSpacing.lg),
                Expanded(
                  child: KeyedSubtree(
                    key: const ValueKey('users-table'),
                    child: data.error != null && data.items.isEmpty
                        ? _TableState(
                            key: const ValueKey('users-error'),
                            icon: DIcons.triangleExclamation,
                            title: 'Directory unavailable',
                            detail: data.error!,
                          )
                        : !data.loaded && data.items.isEmpty
                        ? const _TableState(
                            key: ValueKey('users-loading'),
                            icon: DIcons.users,
                            title: 'Loading users',
                            detail: 'Loading the user directory…',
                            progress: true,
                          )
                        : DDataTable<UserDirectoryItem>(
                            key: ValueKey((
                              widget.siteUrl,
                              data.currentUsername,
                              data.query,
                            )),
                            semanticLabel: 'Users',
                            data: data.items,
                            columns: columns,
                            rowId: (item) => item.id,
                            operationMode: DDataTableOperationMode.manual,
                            rowCount: data.totalRows,
                            virtualized: true,
                            scrollController: _horizontal,
                            verticalScrollController: _vertical,
                            columnWidths: _columnWidths,
                            onColumnWidthsChanged: _resizeColumns,
                            onColumnResizeStart: _beginColumnResize,
                            onColumnResizeEnd: _finishColumnResize,
                            empty: const Text(
                              'No matching users.',
                              key: ValueKey('users-empty'),
                            ),
                            state: DDataTableState(
                              hiddenColumnIds: _hiddenColumnIds,
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
                              if (!setEquals(
                                next.hiddenColumnIds,
                                _hiddenColumnIds,
                              )) {
                                setState(
                                  () => _hiddenColumnIds = Set.of(
                                    next.hiddenColumnIds,
                                  ),
                                );
                              }
                              final sort = next.sort;
                              final order = sort == null
                                  ? null
                                  : orderById[sort.columnId];
                              if (sort != null &&
                                  order != null &&
                                  (order != data.query.order ||
                                      (sort.direction ==
                                              DDataTableSortDirection
                                                  .ascending) !=
                                          data.query.ascending)) {
                                widget.onSortChanged?.call(
                                  order,
                                  sort.direction ==
                                      DDataTableSortDirection.ascending,
                                );
                              }
                            },
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TableState extends StatelessWidget {
  const _TableState({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.progress = false,
  });

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
            const DEmptyContent(
              children: [
                SizedBox(
                  width: 110,
                  child: DProgress(semanticsLabel: 'Loading users'),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

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
