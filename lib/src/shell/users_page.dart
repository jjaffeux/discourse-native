import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/user_directory_column_width_store.dart';

import '../foundation/short_number.dart';
import '../models/user_directory.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import '../utils/pagination.dart';
import 'avatar_image.dart';
import 'directory_skeleton.dart';
import 'search_words.dart';
import 'shell_scope.dart';
import 'user_card.dart';

const String _identityColumnWidthKey = 'identity';

String _metricColumnWidthKey(UserDirectoryColumn column) =>
    'metric.${column.type.name}.${column.id}';

String _columnLabel(
  BuildContext context,
  String siteUrl,
  UserDirectoryColumn column,
) =>
    (PluginRegistryScope.maybeOf(context) ??
            PluginScope.maybeOf(context)?.registry)
        ?.userDirectoryColumnLabel(context, siteUrl, column.name) ??
    column.label;

typedef _MetricCells = ({
  UserDirectoryColumn column,
  double maximum,
  DDataTableCellBuilder<UserDirectoryItem> build,
});

@immutable
final class UsersPageData {
  const UsersPageData({
    this.items = const [],
    this.columns = const [],
    this.groupNames = const [],
    this.currentUsername,
    this.totalRows = 0,
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
  final List<String> groupNames;
  final String? currentUsername;
  final int totalRows;
  final UserDirectoryQuery query;
  final bool loading;
  final bool loadingMore;
  final bool loaded;
  final bool hasMore;
  final String? error;
  final bool pageError;

  @override
  bool operator ==(Object other) =>
      other is UsersPageData &&
      listEquals(other.items, items) &&
      listEquals(other.columns, columns) &&
      listEquals(other.groupNames, groupNames) &&
      other.currentUsername == currentUsername &&
      other.totalRows == totalRows &&
      other.query == query &&
      other.loading == loading &&
      other.loadingMore == loadingMore &&
      other.loaded == loaded &&
      other.hasMore == hasMore &&
      other.error == error &&
      other.pageError == pageError;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(items),
    Object.hashAll(columns),
    Object.hashAll(groupNames),
    currentUsername,
    totalRows,
    query,
    loading,
    loadingMore,
    loaded,
    hasMore,
    error,
    pageError,
  );
}

class UsersDirectoryHost extends StatefulWidget {
  const UsersDirectoryHost({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<UsersDirectoryHost> createState() => _UsersDirectoryHostState();
}

class _UsersDirectoryHostState extends State<UsersDirectoryHost> {
  Object? _owner;
  Object? _scheduledLoad;
  UsersPage? _page;
  Object? _pageRoute;
  List<String> _pageColumnLabels = const [];

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final tab = ShellScope.tabOf(context);
    final route = tab.currentContent;
    final owner = (shell, tab.siteUrl, tab.tabId, tab.lease?.session, route);
    _owner = owner;
    bool owns() =>
        mounted &&
        _owner == owner &&
        identical(ShellScope.read(context), shell) &&
        tab.isCurrent &&
        tab.siteUrl == widget.siteUrl &&
        identical(tab.currentContent, route) &&
        route?.isUsers == true;
    return ListenableBuilder(
      listenable: Listenable.merge([shell.search, shell.userDirectory]),
      builder: (context, _) {
        final instance = shell.instanceFor(widget.siteUrl);
        final query = tab.usersQuery;
        final state = shell.userDirectory.stateFor(widget.siteUrl, query);
        if (owns() && !state.loaded && !state.loading) {
          final load = (owner, query);
          if (_scheduledLoad != load) {
            _scheduledLoad = load;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scheduledLoad != load) return;
              _scheduledLoad = null;
              if (owns() && tab.usersQuery == query) {
                unawaited(tab.loadUsers());
              }
            });
          }
        }
        final data = UsersPageData(
          items: state.items,
          columns: state.columns,
          groupNames: shell.userDirectory.groupNamesFor(widget.siteUrl),
          currentUsername: instance?.user?.username,
          totalRows: state.totalRows,
          query: query,
          loading: state.loading,
          loadingMore: state.loadingMore,
          loaded: state.loaded,
          hasMore: state.hasMore,
          error: state.error,
          pageError: state.pageError,
        );
        final columnLabels = [
          for (final column in data.columns)
            _columnLabel(context, widget.siteUrl, column),
        ];
        // The shell, search and directory controllers each announce changes
        // for every tab, query and account. Handing back the same widget
        // leaves the page and its rows out of the ones that do not apply here.
        // Its callbacks are bound to one route object, and an equal route
        // pushed over it would leave them refusing every action.
        final held = _page;
        if (held != null &&
            identical(_pageRoute, route) &&
            held.key == ValueKey(owner) &&
            held.siteUrl == widget.siteUrl &&
            held.data == data &&
            listEquals(_pageColumnLabels, columnLabels)) {
          return held;
        }
        _pageRoute = route;
        _pageColumnLabels = columnLabels;

        Future<void> reload({bool refresh = true, bool more = false}) async {
          if (owns()) await tab.loadUsers(refresh: refresh, more: more);
        }

        return _page = UsersPage(
          key: ValueKey(owner),
          siteUrl: widget.siteUrl,
          data: data,
          onPeriodChanged: (period) {
            if (owns()) tab.setUsersPeriod(period);
          },
          onSearchChanged: (search) {
            if (owns()) tab.setUsersSearch(search);
          },
          onGroupChanged: (group) {
            if (owns()) tab.setUsersGroup(group);
          },
          onSortChanged: (order, ascending) {
            if (owns()) tab.setUsersOrder(order, ascending);
          },
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
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final UserDirectoryColumnWidthStore columnWidthStore;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late final ValueNotifier<String> _searchText;
  String? _sentSearch;
  Map<String, _MetricCells> _metricCells = const {};
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  Timer? _searchDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _onVerticalScroll() {
    _scheduleLoadMoreCheck();
  }

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
    _searchText = ValueNotifier(widget.data.query.search);
    _deriveMetricCells();
    _vertical.addListener(_onVerticalScroll);

    _restoreColumnWidths();
  }

  @override
  void didUpdateWidget(UsersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged =
        oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.data.currentUsername != widget.data.currentUsername;
    if (ownerChanged) {
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
    final search = widget.data.query.search;
    if (ownerChanged) {
      _searchText.value = search;
      _sentSearch = null;
    } else if (oldWidget.data.query.search != search) {
      // The field's own search comes back trimmed, possibly after further
      // keystrokes: rewriting the field for it would drop trailing whitespace
      // or characters typed since, and move the caret, so only a search the
      // field did not send replaces its text.
      if (search != _sentSearch && search != _searchText.value.trim()) {
        _searchDebounce?.cancel();
        _searchText.value = search;
      }
      _sentSearch = null;
    }
    if (!listEquals(oldWidget.data.items, widget.data.items) ||
        !listEquals(oldWidget.data.columns, widget.data.columns)) {
      _deriveMetricCells();
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
    _searchText.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _deriveMetricCells() {
    final previous = _metricCells;
    final next = <String, _MetricCells>{};
    for (final column in widget.data.columns) {
      final key = _metricColumnWidthKey(column);
      final maximum = widget.data.items.fold<double>(
        0,
        (maximum, item) => math.max(
          maximum,
          item.numericValueFor(column)?.abs().toDouble() ?? 0,
        ),
      );
      final held = previous[key];
      // Keeping the builder keeps the rows: only a column whose scale moved
      // has to draw its bars again when a page lands.
      next[key] =
          held != null &&
              identical(held.column, column) &&
              held.maximum == maximum
          ? held
          : (
              column: column,
              maximum: maximum,
              build: (context, cell) =>
                  _metricCell(context, cell.row, column, maximum),
            );
    }
    _metricCells = next;
  }

  Widget _metricCell(
    BuildContext context,
    UserDirectoryItem item,
    UserDirectoryColumn column,
    double maximum,
  ) {
    final numeric = item.numericValueFor(column);
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
                color: DTokens.of(context).foreground.withValues(alpha: 0.08),
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
    _searchText.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final search = value.trim();
      _sentSearch = search;
      widget.onSearchChanged?.call(search);
    });
  }

  Widget _identityCell(
    BuildContext context,
    DDataTableCellContext<UserDirectoryItem> cell,
  ) => Row(
    key: ValueKey('user-row-${cell.row.user.username}'),
    children: [
      UserCardTarget.avatar(
        username: cell.row.user.username,
        siteUrl: widget.siteUrl.isEmpty ? null : widget.siteUrl,
        child: DAvatar(
          size: DAvatarSize.sm,
          decorative: true,
          child: AvatarImage(
            url: cell.row.user.avatarUrl,
            size: DAvatarSize.sm.dimension,
            fallback: DAvatarFallback(
              child: Text(
                cell.row.user.username.characters.firstOrNull?.toUpperCase() ??
                    '?',
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: DSpacing.sm),
      Flexible(
        child: UserCardTarget(
          username: cell.row.user.username,
          siteUrl: widget.siteUrl.isEmpty ? null : widget.siteUrl,
          child: SearchText(cell.row.user.username),
        ),
      ),
    ],
  );

  Widget _nameCell(
    BuildContext context,
    DDataTableCellContext<UserDirectoryItem> cell,
  ) => cell.row.user.name == null
      ? const Text('—')
      : Align(
          alignment: AlignmentDirectional.centerStart,
          child: UserCardTarget(
            key: ValueKey('user-name-${cell.row.user.username}'),
            username: cell.row.user.username,
            siteUrl: widget.siteUrl.isEmpty ? null : widget.siteUrl,
            child: SearchText(cell.row.user.name!),
          ),
        );

  List<DDataTableColumn<UserDirectoryItem>> _columns(double metricWidth) => [
    DDataTableColumn(
      id: _identityColumnWidthKey,
      label: appL10n.userUserspage,
      hideable: false,
      resizable: true,
      width: const FixedColumnWidth(186),
      minWidth: 120,
      maxWidth: 520,
      compare: widget.onSortChanged == null
          ? null
          : (a, b) => a.user.username.compareTo(b.user.username),
      headerBuilder: _header,
      cellBuilder: _identityCell,
    ),
    DDataTableColumn(
      id: 'name',
      label: appL10n.name,
      resizable: true,
      width: const FixedColumnWidth(186),
      minWidth: 120,
      maxWidth: 800,
      cellBuilder: _nameCell,
    ),
    for (final column in widget.data.columns)
      DDataTableColumn(
        id: _metricColumnWidthKey(column),
        label: _columnLabel(context, widget.siteUrl, column),
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
        cellBuilder: _metricCells[_metricColumnWidthKey(column)]!.build,
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
    final textScale = math.max(
      1.0,
      DReferenceTextScale.scalerOf(context).scale(13) / 13,
    );
    final periodWidth =
        (switch (data.query.period) {
          UserDirectoryPeriod.weekly || UserDirectoryPeriod.yearly => 76.0,
          _ => 96.0,
        }) *
        textScale;

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
    final content = KeyedSubtree(
      key: const ValueKey('users-page'),
      child: DPageReadingLaneBox(
        padding: EdgeInsets.zero,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final toolbarWidth = math.max(
              0.0,
              constraints.maxWidth - DSpacing.lg * 2,
            );
            final stackSearch = constraints.maxWidth < 480 * textScale;
            final searchWidth = stackSearch
                ? toolbarWidth
                : math.min(
                    240.0,
                    math.max(120.0, constraints.maxWidth - 278 - periodWidth),
                  );
            final visibleMetrics = data.columns.where(
              (column) =>
                  !_hiddenColumnIds.contains(_metricColumnWidthKey(column)),
            );
            final fixedWidth =
                (_columnWidths[_identityColumnWidthKey] ?? 186).clamp(
                  120,
                  520,
                ) +
                (_hiddenColumnIds.contains('name')
                    ? 0
                    : (_columnWidths['name'] ?? 186).clamp(120, 800));
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
                ? 132.0
                : math.max(
                    132.0,
                    (toolbarWidth - explicitWidth) / automaticCount,
                  );
            final columns = _columns(metricWidth);
            return DPageSurface.headed(
              key: const ValueKey('users-directory-surface'),
              title: Text(context.l10n.users),
              foldTitleAtTop: true,
              controls: DReferenceTextScale(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      key: const ValueKey('users-toolbar'),
                      spacing: DSpacing.controlGap,
                      runSpacing: DSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: searchWidth,
                          child: ValueListenableBuilder<String>(
                            valueListenable: _searchText,
                            builder: (context, text, _) =>
                                DDataTableFilterField(
                                  key: const ValueKey('users-search'),
                                  size: DControlSize.field,
                                  maxWidth: double.infinity,
                                  value: text,
                                  hintText: context.l10n.filterUsers,
                                  onChanged: _search,
                                ),
                          ),
                        ),
                        SizedBox(
                          width: stackSearch
                              ? toolbarWidth
                              : toolbarWidth -
                                    searchWidth -
                                    DSpacing.controlGap,
                          child: Wrap(
                            alignment: stackSearch
                                ? WrapAlignment.end
                                : WrapAlignment.spaceBetween,
                            spacing: DSpacing.controlGap,
                            runSpacing: DSpacing.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Wrap(
                                spacing: DSpacing.controlGap,
                                runSpacing: DSpacing.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: periodWidth,
                                    ),
                                    child: DSelect<UserDirectoryPeriod>(
                                      size: DControlSize.filter,
                                      key: const ValueKey(
                                        'users-period-filter',
                                      ),
                                      width: periodWidth,
                                      value: data.query.period,
                                      semanticLabel:
                                          context.l10n.activityPeriod,
                                      enabled: widget.onPeriodChanged != null,
                                      onChanged: (value) {
                                        if (value != null) {
                                          widget.onPeriodChanged?.call(value);
                                        }
                                      },
                                      entries: [
                                        for (final period
                                            in UserDirectoryPeriod
                                                .values
                                                .reversed)
                                          DSelectItem(
                                            value: period,
                                            textValue: period.label,
                                            child: Text(period.label),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: math.min(
                                      126 * textScale,
                                      math.max(
                                        0.0,
                                        toolbarWidth -
                                            periodWidth -
                                            DSpacing.controlGap,
                                      ),
                                    ),
                                    child: DCombobox<String>.controlled(
                                      key: const ValueKey('users-group-filter'),
                                      value:
                                          data.query.group ?? '__all_groups__',
                                      anchor: DComboboxInput<String>(
                                        size: DControlSize.filter,
                                        semanticLabel:
                                            context.l10n.filterByGroup,
                                        placeholder: context.l10n.allGroups,
                                      ),
                                      content: DComboboxContent(
                                        children: [
                                          DComboboxEmpty<String>(
                                            child: Text(
                                              context.l10n.noGroupsFound,
                                            ),
                                          ),
                                          const DComboboxList<String>(),
                                        ],
                                      ),
                                      enabled: widget.onGroupChanged != null,
                                      onChanged: (value, reason) =>
                                          widget.onGroupChanged?.call(
                                            value == '__all_groups__'
                                                ? null
                                                : value,
                                          ),
                                      options: [
                                        DComboboxOption(
                                          value: '__all_groups__',
                                          label: context.l10n.allGroups,
                                        ),
                                        for (final group
                                            in (<String>{
                                              ...data.groupNames,
                                              ?data.query.group,
                                            }.toList()..sort(
                                              (a, b) => a
                                                  .toLowerCase()
                                                  .compareTo(b.toLowerCase()),
                                            )))
                                          DComboboxOption(
                                            value: group,
                                            label: group,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              DDataTableColumnToggle<UserDirectoryItem>(
                                key: const ValueKey('users-columns'),
                                size: DControlSize.filter,
                                menuLabel: context.l10n.columns,
                                columns: columns,
                                hiddenColumnIds: _hiddenColumnIds,
                                onChanged: (hidden) => setState(
                                  () => _hiddenColumnIds = Set.of(hidden),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: KeyedSubtree(
                  key: const ValueKey('users-table'),
                  child: data.error != null && data.items.isEmpty
                      ? _TableState(
                          key: const ValueKey('users-error'),
                          icon: DIcons.triangleExclamation,
                          title: context.l10n.directoryUnavailable,
                          detail: data.error!,
                          onRetry: widget.onRefresh == null
                              ? null
                              : () => unawaited(widget.onRefresh!()),
                        )
                      : !data.loaded && data.items.isEmpty
                      ? const DirectorySkeleton(
                          key: ValueKey('users-loading'),
                          kind: DirectorySkeletonKind.users,
                        )
                      : DDataTable<UserDirectoryItem>(
                          key: ValueKey((
                            widget.siteUrl,
                            data.currentUsername,
                            data.query,
                          )),
                          variant: DDataTableVariant.borderless,
                          semanticLabel: context.l10n.users,
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
                          empty: Text(
                            context.l10n.noMatchingUsers,
                            key: const ValueKey('users-empty'),
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
            );
          },
        ),
      ),
    );
    return DScrollChromePagination(
      hasMore: data.hasMore,
      loading: data.loading || data.loadingMore,
      child: content,
    );
  }
}

class _TableState extends StatelessWidget {
  const _TableState({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final VoidCallback? onRetry;
  final DIconData icon;
  final String title;
  final String detail;

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
          if (onRetry != null)
            DEmptyContent(
              children: [
                DButton(label: Text(context.l10n.retry), onPressed: onRetry),
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
  return shortNumber(numeric);
}
