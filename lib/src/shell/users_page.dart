import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../foundation/icons/d_icons.dart';
import '../foundation/icons/d_native_icons.dart';
import '../foundation/short_number.dart';
import '../models/user_directory.dart';
import '../plugin_api/plugin_scope.dart';
import '../utils/pagination.dart';
import 'avatar_image.dart';
import 'directory_skeleton.dart';
import 'search_words.dart';
import 'shell_scope.dart';
import 'user_card_target.dart';

const String _identityColumnId = 'identity';

/// The reference directory's column contents and spacing.
const double _textWidth = 170;
const double _metricWidth = 132;
const double _avatarSize = 22;
const double _controlGap = 8;

String _metricColumnId(UserDirectoryColumn column) =>
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
    this.words = '',
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

  /// The search words the directory was opened on; while they are its
  /// filter they show as a pill, not in the filter field.
  final String words;
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
      other.words == words &&
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
    words,
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
          words: shell.search.wordsFor(widget.siteUrl, tab.tabId, 'users'),
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
          onWordsCleared: () {
            if (owns()) tab.setUsersSearch('');
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
    this.onWordsCleared,
    this.onGroupChanged,
    this.onSortChanged,
    this.onRefresh,
    this.onLoadMore,
  });

  final String siteUrl;
  final UsersPageData data;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onWordsCleared;
  final ValueChanged<String?>? onGroupChanged;
  final void Function(String order, bool ascending)? onSortChanged;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

/// What the filter field holds: the search, unless it is the words a search
/// opened the directory on, which the words pill shows instead.
String _fieldSearch(UsersPageData data) =>
    data.words.isNotEmpty && data.query.search == data.words
    ? ''
    : data.query.search;

const String _allGroups = '__all_groups__';

class _UsersPageState extends State<UsersPage> {
  late final ValueNotifier<String> _searchText;
  String? _sentSearch;
  Map<String, _MetricCells> _metricCells = const {};
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  Timer? _searchDebounce;
  Set<String> _hiddenColumnIds = {};
  bool _loadMoreCheckScheduled = false;
  bool _loadMoreRequested = false;

  @override
  void initState() {
    super.initState();
    _searchText = ValueNotifier(_fieldSearch(widget.data));
    _deriveMetricCells();
    _vertical.addListener(_scheduleLoadMoreCheck);
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
    final search = _fieldSearch(widget.data);
    if (ownerChanged) {
      _searchText.value = search;
      _sentSearch = null;
    } else if (_fieldSearch(oldWidget.data) != search) {
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
      for (final column in widget.data.columns) _metricColumnId(column),
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
    _searchText.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  void _deriveMetricCells() {
    final previous = _metricCells;
    final next = <String, _MetricCells>{};
    for (final column in widget.data.columns) {
      final key = _metricColumnId(column);
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
    final tokens = DTokens.of(context);
    final key = ValueKey('user-metric-${item.user.username}-${column.id}');
    final value = item.valueFor(column);
    if (column.type == UserDirectoryColumnType.userField) {
      final missing = _isMissing(value);
      return Text(
        missing ? '—' : _formatValue(value, column, null),
        key: key,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          color: Color.lerp(
            tokens.background,
            tokens.foreground,
            missing ? .5 : .62,
          ),
        ),
      );
    }
    final numeric = item.numericValueFor(column);
    final fraction = maximum > 0 && numeric != null
        ? (numeric.abs() / maximum).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return SizedBox(
      key: key,
      height: 20,
      child: Stack(
        children: [
          if (fraction > 0)
            Positioned.fill(
              child: ExcludeSemantics(
                child: DChartBar(
                  fraction: fraction,
                  color: tokens.raisedBackground,
                  radius: 3,
                ),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: Text(
                _formatValue(value, column, numeric),
                style: TextStyle(
                  fontSize: 13,
                  color: Color.lerp(tokens.background, tokens.foreground, .9),
                ),
              ),
            ),
          ),
        ],
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
    final paging = ScrollPagingGate(
      hasMore: widget.data.hasMore,
      busy:
          _loadMoreRequested || widget.data.loading || widget.data.loadingMore,
      lastPageFailed: widget.data.pageError,
    );
    if (widget.onLoadMore == null || !paging.admits) return;
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
  ) {
    final siteUrl = widget.siteUrl.isEmpty ? null : widget.siteUrl;
    final username = cell.row.user.username;
    return Row(
      key: ValueKey('user-row-$username'),
      children: [
        UserCardTarget.avatar(
          username: username,
          siteUrl: siteUrl,
          child: DAvatar(
            dimension: _avatarSize,
            decorative: true,
            child: AvatarImage(
              url: cell.row.user.avatarUrl,
              size: _avatarSize,
              fallback: DAvatarFallback(
                child: Text(
                  username.characters.firstOrNull?.toUpperCase() ?? '?',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: UserCardTarget(
            username: username,
            siteUrl: siteUrl,
            child: SearchText(
              username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: DTokens.of(context).foreground,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _nameCell(
    BuildContext context,
    DDataTableCellContext<UserDirectoryItem> cell,
  ) {
    final name = cell.row.user.name;
    if (name == null) return const SizedBox.shrink();
    final tokens = DTokens.of(context);
    return UserCardTarget(
      key: ValueKey('user-name-${cell.row.user.username}'),
      username: cell.row.user.username,
      siteUrl: widget.siteUrl.isEmpty ? null : widget.siteUrl,
      child: SearchText(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          color: Color.lerp(tokens.background, tokens.foreground, .9),
        ),
      ),
    );
  }

  /// A header that orders the directory by [order] when pressed: first
  /// ascending for a name, descending for a count, then the other way.
  DDataTableHeaderBuilder<UserDirectoryItem> _header(
    String? order, {
    required bool ascendingFirst,
  }) => (context, header) {
    final query = widget.data.query;
    final sorted = order != null && query.order == order;
    final sort = widget.onSortChanged;
    return _SortHeader(
      label: header.column.label,
      direction: !sorted
          ? null
          : query.ascending
          ? DDataTableSortDirection.ascending
          : DDataTableSortDirection.descending,
      onSort: order == null || sort == null
          ? null
          : () => sort(order, sorted ? !query.ascending : ascendingFirst),
    );
  };

  List<DDataTableColumn<UserDirectoryItem>> _columns(BuildContext context) => [
    DDataTableColumn(
      id: _identityColumnId,
      label: appL10n.userUserspage,
      hideable: false,
      width: const FixedColumnWidth(_textWidth),
      headerBuilder: _header('username', ascendingFirst: true),
      cellBuilder: _identityCell,
    ),
    DDataTableColumn(
      id: 'name',
      label: appL10n.name,
      width: const FixedColumnWidth(_textWidth),
      headerBuilder: _header(null, ascendingFirst: true),
      cellBuilder: _nameCell,
    ),
    for (final column in widget.data.columns)
      DDataTableColumn(
        id: _metricColumnId(column),
        label: _columnLabel(context, widget.siteUrl, column),
        width: FixedColumnWidth(
          column.type == UserDirectoryColumnType.userField
              ? _textWidth
              : _metricWidth,
        ),
        headerBuilder: _header(
          column.name,
          ascendingFirst: column.type == UserDirectoryColumnType.userField,
        ),
        alignment: column.type == UserDirectoryColumnType.userField
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        cellBuilder: _metricCells[_metricColumnId(column)]!.build,
      ),
  ];

  Widget _toolbar(
    BuildContext context,
    List<DDataTableColumn<UserDirectoryItem>> columns,
  ) {
    final data = widget.data;
    final textScale = math.max(
      1.0,
      DReferenceTextScale.scalerOf(context).scale(13) / 13,
    );
    final groups = <String>{...data.groupNames, ?data.query.group}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Row(
      key: const ValueKey('users-toolbar'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.words.isNotEmpty) ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 128 * textScale),
            child: DButton(
              key: const ValueKey('users-search-words'),
              variant: DButtonVariant.quietSelected,
              size: DButtonSize.filter,
              icon: const DIcon(DIcons.magnifyingGlass, size: 11),
              label: Text(
                '“${data.words}”',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const DIcon(DIcons.xmark, size: 10),
              tooltip: context.l10n.clearSearch,
              semanticLabel: '${context.l10n.clearSearch}: ${data.words}',
              onPressed: widget.onWordsCleared,
            ),
          ),
          const SizedBox(width: _controlGap),
        ],
        Expanded(
          child: _FilterRun(
            basis: 220 * textScale,
            grow: DPageHeaderHost.titlesInBarOf(context),
            children: [
              ValueListenableBuilder<String>(
                valueListenable: _searchText,
                builder: (context, text, _) => DDataTableFilterField(
                  key: const ValueKey('users-search'),
                  size: DControlSize.field,
                  maxWidth: double.infinity,
                  value: text,
                  hintText: context.l10n.filterUsers,
                  onChanged: _search,
                ),
              ),
              DSelect<UserDirectoryPeriod>(
                key: const ValueKey('users-period-filter'),
                size: DControlSize.filter,
                width: 88 * textScale,
                value: data.query.period,
                semanticLabel: context.l10n.activityPeriod,
                enabled: widget.onPeriodChanged != null,
                onChanged: (value) {
                  if (value != null) widget.onPeriodChanged?.call(value);
                },
                entries: [
                  for (final period in UserDirectoryPeriod.values.reversed)
                    DSelectItem(
                      value: period,
                      textValue: period.label,
                      child: Text(period.label),
                    ),
                ],
              ),
              DSelect<String>(
                key: const ValueKey('users-group-filter'),
                size: DControlSize.filter,
                width: 96 * textScale,
                value: data.query.group ?? _allGroups,
                semanticLabel: context.l10n.filterByGroup,
                enabled: widget.onGroupChanged != null,
                onChanged: (value) {
                  if (value == null) return;
                  widget.onGroupChanged?.call(
                    value == _allGroups ? null : value,
                  );
                },
                entries: [
                  DSelectItem(
                    value: _allGroups,
                    textValue: context.l10n.allGroups,
                    child: Text(context.l10n.allGroups),
                  ),
                  for (final group in groups)
                    DSelectItem(
                      value: group,
                      textValue: group,
                      child: Text(group),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: _controlGap),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 96 * textScale),
          child: DDataTableColumnToggle<UserDirectoryItem>(
            key: const ValueKey('users-columns'),
            size: DControlSize.filter,
            menuLabel: context.l10n.columns,
            columns: columns,
            hiddenColumnIds: _hiddenColumnIds,
            onChanged: (hidden) =>
                setState(() => _hiddenColumnIds = Set.of(hidden)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    _scheduleLoadMoreCheck();
    final columns = _columns(context);
    final tokens = DTokens.of(context);
    final content = KeyedSubtree(
      key: const ValueKey('users-page'),
      child: DPageReadingLaneBox(
        padding: EdgeInsets.zero,
        child: DPageSurface.headed(
          key: const ValueKey('users-directory-surface'),
          title: Text(
            data.words.isEmpty
                ? context.l10n.users
                : context.l10n.searchWordsInUsers(data.words),
          ),
          controls: DReferenceTextScale(child: _toolbar(context, columns)),
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
                    variant: DDataTableVariant.directory,
                    semanticLabel: context.l10n.users,
                    data: data.items,
                    columns: columns,
                    rowId: (item) => item.id,
                    operationMode: DDataTableOperationMode.manual,
                    rowCount: data.totalRows,
                    virtualized: true,
                    scrollController: _horizontal,
                    verticalScrollController: _vertical,
                    empty: Text(
                      context.l10n.noUsersMatchFilter,
                      key: const ValueKey('users-empty'),
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Color.lerp(
                          tokens.background,
                          tokens.foreground,
                          .5,
                        ),
                      ),
                    ),
                    state: DDataTableState(hiddenColumnIds: _hiddenColumnIds),
                    onStateChanged: (next) {
                      if (setEquals(next.hiddenColumnIds, _hiddenColumnIds)) {
                        return;
                      }
                      setState(
                        () => _hiddenColumnIds = Set.of(next.hiddenColumnIds),
                      );
                    },
                  ),
          ),
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

/// A column label that orders the directory when pressed, with the
/// reference's sort mark: both chevrons faint until the column is the order,
/// then the one for its direction.
class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.label,
    required this.direction,
    required this.onSort,
  });

  final String label;
  final DDataTableSortDirection? direction;
  final VoidCallback? onSort;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final sorted = direction != null;
    final color = sorted
        ? tokens.foreground
        : Color.lerp(tokens.background, tokens.foreground, .62)!;
    final faint = Color.lerp(tokens.background, tokens.foreground, .5)!;
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        if (onSort != null) ...[
          const SizedBox(width: 6),
          switch (direction) {
            DDataTableSortDirection.ascending => DIcon(
              DNativeIcons.chevronUp,
              size: 9,
              color: color,
            ),
            DDataTableSortDirection.descending => DIcon(
              DIcons.chevronDown,
              size: 9,
              color: color,
            ),
            null => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DIcon(DNativeIcons.chevronUp, size: 7, color: faint),
                const SizedBox(height: 1),
                DIcon(DIcons.chevronDown, size: 7, color: faint),
              ],
            ),
          },
        ],
      ],
    );
    final sort = onSort;
    if (sort == null) return title;
    return Semantics(
      button: true,
      label: switch (direction) {
        DDataTableSortDirection.ascending => context.l10n.sortedAscending(
          label,
        ),
        DDataTableSortDirection.descending => context.l10n.sortedDescending(
          label,
        ),
        null => context.l10n.notSorted(label),
      },
      onTap: sort,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              sort();
              return null;
            },
          ),
        },
        child: DTouchTarget(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: sort,
            child: title,
          ),
        ),
      ),
    );
  }
}

/// The search field and the filter pills as the reference's wrapping flex
/// row lays them out: the field at [basis], then each pill at its own width
/// while it still fits on the line, on the next line once it does not. With
/// [grow] the field then takes whatever its own line has left over.
class _FilterRun extends MultiChildRenderObjectWidget {
  const _FilterRun({
    required this.basis,
    required this.grow,
    required super.children,
  });

  final double basis;
  final bool grow;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFilterRun(
    basis: basis,
    grow: grow,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFilterRun renderObject,
  ) => renderObject
    ..basis = basis
    ..grow = grow
    ..textDirection = Directionality.of(context);
}

final class _FilterRunParentData extends ContainerBoxParentData<RenderBox> {}

final class _RenderFilterRun extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FilterRunParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FilterRunParentData> {
  _RenderFilterRun({
    required this._basis,
    required this._grow,
    required this._textDirection,
  });

  double get basis => _basis;
  double _basis;
  set basis(double value) {
    if (value == _basis) return;
    _basis = value;
    markNeedsLayout();
  }

  bool get grow => _grow;
  bool _grow;
  set grow(bool value) {
    if (value == _grow) return;
    _grow = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FilterRunParentData) {
      child.parentData = _FilterRunParentData();
    }
  }

  Size _layout(
    BoxConstraints constraints,
    ChildLayouter layoutChild, {
    required bool place,
  }) {
    final field = firstChild;
    if (field == null) return constraints.smallest;
    final maxWidth = constraints.maxWidth;
    final pills = <(RenderBox, Size)>[
      for (
        var child = childAfter(field);
        child != null;
        child = childAfter(child)
      )
        (child, layoutChild(child, BoxConstraints(maxWidth: maxWidth))),
    ];
    var fieldWidth = math.min(basis, maxWidth);
    final lines = <List<(RenderBox, Size)>>[[]];
    final widths = [fieldWidth];
    for (final pill in pills) {
      final width = pill.$2.width;
      if (widths.last + _controlGap + width <=
          maxWidth + precisionErrorTolerance) {
        lines.last.add(pill);
        widths.last += _controlGap + width;
      } else {
        lines.add([pill]);
        widths.add(width);
      }
    }
    if (grow) {
      fieldWidth += math.max(0.0, maxWidth - widths.first);
      widths.first = maxWidth;
    }
    final fieldSize = layoutChild(
      field,
      BoxConstraints.tightFor(width: fieldWidth),
    );
    final width = constraints.constrainWidth(widths.reduce(math.max));
    var top = 0.0;
    for (final (index, line) in lines.indexed) {
      if (index > 0) top += _controlGap;
      var start = 0.0;
      var height = 0.0;
      if (index == 0) {
        if (place) _place(field, start, top, fieldSize.width, width);
        start = fieldSize.width + _controlGap;
        height = fieldSize.height;
      }
      for (final (child, size) in line) {
        if (place) _place(child, start, top, size.width, width);
        start += size.width + _controlGap;
        height = math.max(height, size.height);
      }
      top += height;
    }
    return constraints.constrain(Size(width, top));
  }

  void _place(
    RenderBox child,
    double start,
    double top,
    double extent,
    double width,
  ) {
    (child.parentData! as _FilterRunParentData).offset = Offset(
      textDirection == TextDirection.rtl ? width - start - extent : start,
      top,
    );
  }

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, place: true);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild, place: false);

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  double computeMinIntrinsicWidth(double height) {
    var width = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      width = math.max(width, child.getMinIntrinsicWidth(height));
    }
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = -_controlGap;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      width += _controlGap + child.getMaxIntrinsicWidth(height);
    }
    return math.max(0.0, width);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
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

bool _isMissing(Object? value) => switch (value) {
  null => true,
  String() => value.trim().isEmpty,
  List() => value.whereType<Object>().isEmpty,
  _ => false,
};

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
