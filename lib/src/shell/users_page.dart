import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../data/user_directory_column_width_store.dart';
import '../models/user_directory.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'choice_menu.dart';
import 'shell_scope.dart';
import 'user_card.dart';
import 'user_directory_controller.dart';

const String _identityColumnWidthKey = 'identity';

bool _usesTouchTargets(ThemeData theme) =>
    theme.platform == TargetPlatform.iOS ||
    theme.platform == TargetPlatform.android;

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
  static const double _rowHeight = 56;
  static const double _headerHeight = 42;
  static const double _metricWidth = 132;

  late final TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _horizontal = ScrollController();
  final ScrollController _identityVertical = ScrollController();
  final ScrollController _metricsVertical = ScrollController();
  Timer? _searchDebounce;
  int _ownerGeneration = 0;
  Set<int>? _visibleColumnIds;
  final ValueNotifier<int?> _hoveredId = ValueNotifier(null);
  Map<int, double> _columnMaxima = const {};
  bool _syncingVerticalScroll = false;
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
    _identityVertical.addListener(_identityScrolled);
    _metricsVertical.addListener(_metricsScrolled);
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
    if (ownerChanged || oldWidget.data.query != widget.data.query) {
      _hoveredId.value = null;
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
    _identityVertical.dispose();
    _metricsVertical.dispose();
    _hoveredId.dispose();
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

  void _resizeColumn(String key, double width) {
    if (!width.isFinite || _columnWidths[key] == width) return;
    _columnWidthInteractionGeneration++;
    setState(() {
      _columnWidths = {..._columnWidths, key: width};
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
    final generation = _ownerGeneration;
    final columns = widget.data.columns;
    final draft = Set<int>.from(
      _visibleColumnIds ?? columns.map((column) => column.id),
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
                  for (final column in columns)
                    DCheckbox(
                      key: ValueKey('users-column-${column.id}'),
                      value: draft.contains(column.id),
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
                  ..addAll(columns.map((column) => column.id));
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
    if (!mounted || generation != _ownerGeneration || result == null) return;
    setState(() => _visibleColumnIds = result);
  }

  Future<void> _manageColumns() async {
    final generation = _ownerGeneration;
    final save = widget.onManageColumns;
    if (save == null) return;
    var draft = [...widget.data.availableColumns]
      ..sort((a, b) => a.position.compareTo(b.position));
    final result = await showDialog<List<UserDirectoryColumn>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) {
          final canSave = draft.any((column) => column.enabled);
          final theme = Theme.of(context);
          return AlertDialog(
            key: const ValueKey('users-manage-columns-dialog'),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Text('Directory columns', style: theme.textTheme.titleLarge),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            content: SizedBox(
              key: const ValueKey('users-manage-columns-content'),
              width: 560,
              child: ConstrainedBox(
                key: const ValueKey('users-manage-columns-list'),
                constraints: const BoxConstraints(maxHeight: 600),
                child: ListView(
                  shrinkWrap: true,
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
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                draft[index].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                switch (draft[index].type) {
                                  UserDirectoryColumnType.automatic =>
                                    'Activity',
                                  UserDirectoryColumnType.userField =>
                                    'User field',
                                  UserDirectoryColumnType.plugin => 'Plugin',
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              onChanged: (enabled) => updateDialog(() {
                                draft[index] = draft[index].copyWith(
                                  enabled: enabled ?? false,
                                );
                              }),
                            ),
                          ),
                          Row(
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
                                insetSurface: true,
                                variant: DButtonVariant.transparent,
                                icon: const DIcon(DIcons.arrowUp, size: 13),
                              ),
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
                                insetSurface: true,
                                variant: DButtonVariant.transparent,
                                icon: Transform.rotate(
                                  angle: math.pi,
                                  child: const DIcon(DIcons.arrowUp, size: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                label: const Text('Save changes'),
                variant: DButtonVariant.primary,
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
          columnWidths: _columnWidths,
          columnMaxima: _columnMaxima,
          hoveredId: _hoveredId,
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
          onColumnResizeStart: _beginColumnResize,
          onColumnResize: _resizeColumn,
          onColumnResizeEnd: _finishColumnResize,
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
    required this.columnWidths,
    required this.columnMaxima,
    required this.hoveredId,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onPeriodChanged,
    required this.onGroupChanged,
    required this.onSort,
    required this.onColumnResizeStart,
    required this.onColumnResize,
    required this.onColumnResizeEnd,
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
  final Map<String, double> columnWidths;
  final Map<int, double> columnMaxima;
  final ValueNotifier<int?> hoveredId;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;
  final ValueChanged<String?>? onGroupChanged;
  final ValueChanged<String> onSort;
  final VoidCallback onColumnResizeStart;
  final void Function(String key, double width) onColumnResize;
  final VoidCallback onColumnResizeEnd;
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
            columnWidths: columnWidths,
            columnMaxima: columnMaxima,
            hoveredId: hoveredId,
            onSort: onSort,
            onColumnResizeStart: onColumnResizeStart,
            onColumnResize: onColumnResize,
            onColumnResizeEnd: onColumnResizeEnd,
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
    final controlHeight = _usesTouchTargets(theme)
        ? 48.0
        : DButton.iconOnlyDimensionFor(DButtonSize.small);
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
              : DTooltip(
                  message: 'Clear search',
                  labelTrigger: true,
                  child: IconButton(
                    tooltip: '',
                    onPressed: onClearSearch,
                    icon: DIcon(
                      DIcons.xmark,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
                  style: theme.textTheme.labelMedium?.copyWith(
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
    required this.columnWidths,
    required this.columnMaxima,
    required this.hoveredId,
    required this.onSort,
    required this.onColumnResizeStart,
    required this.onColumnResize,
    required this.onColumnResizeEnd,
  });

  static const double _minimumIdentityWidth = 180;
  static const double _maximumIdentityWidth = 520;
  static const double _minimumMetricsViewportWidth = 72;
  static const double _minimumMetricWidth = 88;
  static const double _maximumMetricWidth = 4096;

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
  final Map<String, double> columnWidths;
  final Map<int, double> columnMaxima;
  final ValueNotifier<int?> hoveredId;
  final ValueChanged<String> onSort;
  final VoidCallback onColumnResizeStart;
  final void Function(String key, double width) onColumnResize;
  final VoidCallback onColumnResizeEnd;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final defaultIdentityWidth = constraints.maxWidth < 560 ? 220.0 : 258.0;
        final maximumIdentityWidth = math.max(
          0.0,
          math.min(
            _maximumIdentityWidth,
            constraints.maxWidth - _minimumMetricsViewportWidth,
          ),
        );
        final minimumIdentityWidth = math.min(
          _minimumIdentityWidth,
          maximumIdentityWidth,
        );
        final identityWidth =
            (columnWidths[_identityColumnWidthKey] ?? defaultIdentityWidth)
                .clamp(minimumIdentityWidth, maximumIdentityWidth)
                .toDouble();
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.line)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('users-identity-column-width'),
                width: identityWidth,
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
                      width: identityWidth,
                      minimumWidth: minimumIdentityWidth,
                      maximumWidth: maximumIdentityWidth,
                      onResizeStart: onColumnResizeStart,
                      onResize: (width) =>
                          onColumnResize(_identityColumnWidthKey, width),
                      onResizeEnd: onColumnResizeEnd,
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
                              hoveredId: hoveredId,
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
                    final explicitWidthTotal = columns.fold<double>(0, (
                      total,
                      column,
                    ) {
                      final stored =
                          columnWidths[_metricColumnWidthKey(column)];
                      if (stored == null) return total;
                      return total +
                          stored
                              .clamp(_minimumMetricWidth, _maximumMetricWidth)
                              .toDouble();
                    });
                    final automaticColumnCount = columns
                        .where(
                          (column) =>
                              columnWidths[_metricColumnWidthKey(column)] ==
                              null,
                        )
                        .length;
                    final automaticWidth = automaticColumnCount == 0
                        ? metricWidth
                        : math.max(
                            metricWidth,
                            (metricConstraints.maxWidth - explicitWidthTotal) /
                                automaticColumnCount,
                          );
                    final resolvedMetricWidths = [
                      for (final column in columns)
                        (columnWidths[_metricColumnWidthKey(column)] ??
                                automaticWidth)
                            .clamp(_minimumMetricWidth, _maximumMetricWidth)
                            .toDouble(),
                    ];
                    final resolvedMetricWidthTotal = resolvedMetricWidths
                        .fold<double>(0, (total, width) => total + width);
                    final contentWidth = math.max(
                      metricConstraints.maxWidth,
                      resolvedMetricWidthTotal,
                    );
                    final hasFiller =
                        resolvedMetricWidthTotal < contentWidth - .01;
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
                                    for (
                                      var index = 0;
                                      index < columns.length;
                                      index++
                                    )
                                      SizedBox(
                                        key: ValueKey(
                                          'users-metric-column-width-${columns[index].id}',
                                        ),
                                        width: resolvedMetricWidths[index],
                                        child: _MetricHeader(
                                          palette: palette,
                                          column: columns[index],
                                          sorted:
                                              data.query.order ==
                                              columns[index].name,
                                          ascending: data.query.ascending,
                                          onSort: () =>
                                              onSort(columns[index].name),
                                          width: resolvedMetricWidths[index],
                                          minimumWidth: _minimumMetricWidth,
                                          maximumWidth: _maximumMetricWidth,
                                          onResizeStart: onColumnResizeStart,
                                          onResize: (width) => onColumnResize(
                                            _metricColumnWidthKey(
                                              columns[index],
                                            ),
                                            width,
                                          ),
                                          onResizeEnd: onColumnResizeEnd,
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
                                    if (columns.isNotEmpty && hasFiller)
                                      Expanded(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: palette.tableHeader,
                                            border: Border(
                                              bottom: BorderSide(
                                                color: palette.line,
                                              ),
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
                                        return _RowHover(
                                          id: item.id,
                                          hoveredId: hoveredId,
                                          builder: (context, hovered, child) =>
                                              ColoredBox(
                                                key: ValueKey(
                                                  'user-metrics-background-${item.user.username}',
                                                ),
                                                color: _rowColor(
                                                  palette,
                                                  currentUser: currentUser,
                                                  hovered: hovered,
                                                ),
                                                child: child,
                                              ),
                                          child: Row(
                                            children: [
                                              for (
                                                var columnIndex = 0;
                                                columnIndex < columns.length;
                                                columnIndex++
                                              )
                                                SizedBox(
                                                  width:
                                                      resolvedMetricWidths[columnIndex],
                                                  child: _MetricCell(
                                                    palette: palette,
                                                    item: item,
                                                    column:
                                                        columns[columnIndex],
                                                    maximum:
                                                        columnMaxima[columns[columnIndex]
                                                            .id] ??
                                                        0,
                                                  ),
                                                ),
                                              if (hasFiller)
                                                Expanded(
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      border: Border(
                                                        bottom: BorderSide(
                                                          color:
                                                              palette.rowLine,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
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
    required this.width,
    required this.minimumWidth,
    required this.maximumWidth,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
  });

  final _MatrixPalette palette;
  final double height;
  final bool ascending;
  final bool sorted;
  final VoidCallback onSort;
  final double width;
  final double minimumWidth;
  final double maximumWidth;
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;

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
    child: Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 14),
          child: _HeaderButton(
            label: 'User',
            sorted: sorted,
            ascending: ascending,
            palette: palette,
            onPressed: onSort,
            alignment: AlignmentDirectional.centerStart,
          ),
        ),
        UsersColumnResizeHandle(
          resizeKey: 'users-resize-identity',
          semanticsLabel: 'Resize User column',
          width: width,
          minimumWidth: minimumWidth,
          maximumWidth: maximumWidth,
          onResizeStart: onResizeStart,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
        ),
      ],
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
    required this.width,
    required this.minimumWidth,
    required this.maximumWidth,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
  });

  final _MatrixPalette palette;
  final UserDirectoryColumn column;
  final bool sorted;
  final bool ascending;
  final VoidCallback onSort;
  final double width;
  final double minimumWidth;
  final double maximumWidth;
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: palette.tableHeader,
      border: Border(
        right: BorderSide(color: palette.line),
        bottom: BorderSide(color: palette.line),
      ),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, end: 14),
          child: _HeaderButton(
            label: column.label,
            sorted: sorted,
            ascending: ascending,
            palette: palette,
            onPressed: onSort,
            alignment: AlignmentDirectional.centerEnd,
          ),
        ),
        UsersColumnResizeHandle(
          key: ValueKey('users-resize-${column.id}'),
          resizeKey: 'users-resize-${column.id}',
          semanticsLabel: 'Resize ${column.label} column',
          width: width,
          minimumWidth: minimumWidth,
          maximumWidth: maximumWidth,
          onResizeStart: onResizeStart,
          onResize: onResize,
          onResizeEnd: onResizeEnd,
        ),
      ],
    ),
  );
}

/// Column-edge adapter shared by the directory and local native review fixture.
class UsersColumnResizeHandle extends StatelessWidget {
  const UsersColumnResizeHandle({
    super.key,
    required this.resizeKey,
    required this.semanticsLabel,
    required this.width,
    required this.minimumWidth,
    required this.maximumWidth,
    required this.onResizeStart,
    required this.onResize,
    required this.onResizeEnd,
  });

  static const double keyboardStep = 16;

  final String resizeKey;
  final String semanticsLabel;
  final double width;
  final double minimumWidth;
  final double maximumWidth;
  final VoidCallback onResizeStart;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) => PositionedDirectional(
    end: 0,
    top: 0,
    bottom: 0,
    width: DResizableHandle.resolveHitExtent(context, 12),
    child: DResizableHandle.standalone(
      focusKey: ValueKey('$resizeKey-focus'),
      semanticsKey: ValueKey('$resizeKey-semantics'),
      gestureKey: ValueKey('$resizeKey-handle'),
      semanticLabel: semanticsLabel,
      value: width,
      min: minimumWidth,
      max: maximumWidth,
      keyboardStep: keyboardStep,
      dividerAlignment: AlignmentDirectional.centerEnd,
      valueFormatter: (value) => '${value.round()} pixels wide',
      onChangeStart: onResizeStart,
      onChanged: onResize,
      onChangeEnd: onResizeEnd,
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
  final AlignmentGeometry alignment;

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
                  textAlign:
                      alignment == Alignment.centerRight ||
                          alignment == AlignmentDirectional.centerEnd
                      ? TextAlign.right
                      : TextAlign.left,
                  style: theme.textTheme.labelMedium?.copyWith(
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

class _RowHover extends StatefulWidget {
  const _RowHover({
    required this.id,
    required this.hoveredId,
    required this.builder,
    required this.child,
  });

  final int id;
  final ValueNotifier<int?> hoveredId;
  final Widget Function(BuildContext context, bool hovered, Widget child)
  builder;
  final Widget child;

  @override
  State<_RowHover> createState() => _RowHoverState();
}

class _RowHoverState extends State<_RowHover> {
  late bool _hovered;

  @override
  void initState() {
    super.initState();
    _hovered = widget.hoveredId.value == widget.id;
    widget.hoveredId.addListener(_hoverChanged);
  }

  @override
  void didUpdateWidget(_RowHover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hoveredId != widget.hoveredId) {
      oldWidget.hoveredId.removeListener(_hoverChanged);
      widget.hoveredId.addListener(_hoverChanged);
    }
    _hovered = widget.hoveredId.value == widget.id;
  }

  void _hoverChanged() {
    final hovered = widget.hoveredId.value == widget.id;
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  void dispose() {
    widget.hoveredId.removeListener(_hoverChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => widget.hoveredId.value = widget.id,
    onExit: (_) {
      if (widget.hoveredId.value == widget.id) widget.hoveredId.value = null;
    },
    child: widget.builder(context, _hovered, widget.child),
  );
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    super.key,
    required this.palette,
    required this.item,
    required this.siteUrl,
    required this.currentUser,
    required this.hoveredId,
  });

  final _MatrixPalette palette;
  final UserDirectoryItem item;
  final String siteUrl;
  final bool currentUser;
  final ValueNotifier<int?> hoveredId;

  @override
  Widget build(BuildContext context) => _RowHover(
    id: item.id,
    hoveredId: hoveredId,
    builder: (context, hovered, child) => Container(
      key: ValueKey('user-identity-background-${item.user.username}'),
      decoration: BoxDecoration(
        color: _rowColor(palette, currentUser: currentUser, hovered: hovered),
        border: Border(
          right: BorderSide(color: palette.line),
          bottom: BorderSide(color: palette.rowLine),
        ),
      ),
      child: child,
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
                  DAvatar.frame(
                    key: ValueKey('user-avatar-${item.user.username}'),
                    borderRadius: Theme.of(context).avatars.borderRadiusFor(32),
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
                                  style: Theme.of(context).textTheme.labelMedium
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
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: palette.faint),
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
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
            LayoutBuilder(
              builder: (context, constraints) => Center(
                child: DChartBar(
                  fraction: math.max(.06, intensity),
                  height: constraints.maxHeight * .64,
                  color: palette.accent.withValues(
                    alpha: palette.accent.a * (.12 + intensity * .18),
                  ),
                ),
              ),
            ),
          Align(
            alignment: userField ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              _formatValue(item.valueFor(column), column, numeric),
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
