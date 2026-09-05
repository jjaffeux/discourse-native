import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';

import '../models/user_directory.dart';
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
    this.groupNames = const [],
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
  final List<String> groupNames;
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
            groupNames: state.groupNames,
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
  });

  final String siteUrl;
  final UsersPageData data;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String?>? onGroupChanged;
  final void Function(String order, bool ascending)? onSortChanged;
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
  final Set<int> _selectedIds = {};
  int? _hoveredId;
  bool _syncingVerticalScroll = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.data.query.search);
    _identityVertical.addListener(
      () => _syncVertical(_identityVertical, _metricsVertical),
    );
    _metricsVertical.addListener(
      () => _syncVertical(_metricsVertical, _identityVertical),
    );
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
    if (oldWidget.data.query != widget.data.query) {
      _selectedIds.clear();
    } else {
      final currentIds = {for (final item in widget.data.items) item.id};
      _selectedIds.removeWhere((id) => !currentIds.contains(id));
    }
    final oldIds = {for (final column in oldWidget.data.columns) column.id};
    final newIds = {for (final column in widget.data.columns) column.id};
    final configured = _visibleColumnIds;
    if (configured != null && !setEquals(oldIds, newIds)) {
      configured
        ..removeWhere((id) => !newIds.contains(id))
        ..addAll(newIds.difference(oldIds));
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
            TextButton(
              onPressed: () => updateDialog(() {
                draft
                  ..clear()
                  ..addAll(widget.data.columns.map((column) => column.id));
              }),
              child: const Text('Show all'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, draft),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _visibleColumnIds = result);
  }

  void _toggleRow(int id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleAll(bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.addAll(widget.data.items.map((item) => item.id));
      } else {
        _selectedIds.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = _MatrixPalette.of(context);
    final columns = _visibleColumns;
    return ColoredBox(
      color: palette.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final low = constraints.maxHeight < 620;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 24,
              low ? 10 : 20,
              compact ? 10 : 24,
              compact ? 10 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!low)
                  _DirectoryHero(
                    data: widget.data,
                    palette: palette,
                    compact: compact,
                  ),
                Expanded(
                  child: _DirectorySurface(
                    siteUrl: widget.siteUrl,
                    palette: palette,
                    data: widget.data,
                    columns: columns,
                    compact: compact,
                    searchController: _searchController,
                    searchFocus: _searchFocus,
                    horizontal: _horizontal,
                    identityVertical: _identityVertical,
                    metricsVertical: _metricsVertical,
                    rowHeight: _rowHeight,
                    headerHeight: _headerHeight,
                    metricWidth: _metricWidth,
                    selectedIds: _selectedIds,
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
                    onDirectionChanged: () => widget.onSortChanged?.call(
                      widget.data.query.order,
                      !widget.data.query.ascending,
                    ),
                    onChooseColumns: _chooseColumns,
                    onToggleRow: _toggleRow,
                    onToggleAll: _toggleAll,
                    onRefresh: widget.onRefresh,
                    onLoadMore: widget.onLoadMore,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DirectoryHero extends StatelessWidget {
  const _DirectoryHero({
    required this.data,
    required this.palette,
    required this.compact,
  });

  final UsersPageData data;
  final _MatrixPalette palette;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'DATASET / DIRECTORY_ITEMS',
          style: TextStyle(
            color: palette.green,
            fontFamily: 'monospace',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.25,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Community signal',
          style: TextStyle(
            color: palette.ink,
            fontSize: compact ? 28 : 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            height: 1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Every contribution, sortable and close at hand.',
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 1, 4, 14),
        child: copy,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: copy),
          _MetaCard(
            label: 'People',
            value: data.loaded ? _formatCompact(data.totalRows) : '—',
            palette: palette,
          ),
          const SizedBox(width: 8),
          _MetaCard(
            label: 'Window',
            value: data.query.period.label,
            palette: palette,
          ),
          const SizedBox(width: 8),
          _MetaCard(
            label: 'Updated',
            value: _formatUpdated(data.lastUpdatedAt),
            palette: palette,
            small: true,
          ),
        ],
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  const _MetaCard({
    required this.label,
    required this.value,
    required this.palette,
    this.small = false,
  });

  final String label;
  final String value;
  final _MatrixPalette palette;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    height: 68,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: palette.heroCard,
      border: Border.all(color: palette.line),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: palette.faint,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
          ),
        ),
        const Spacer(),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.ink,
            fontFamily: 'monospace',
            fontSize: small ? 11 : 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
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
    required this.selectedIds,
    required this.hoveredId,
    required this.onHover,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.onPeriodChanged,
    required this.onGroupChanged,
    required this.onSort,
    required this.onDirectionChanged,
    required this.onChooseColumns,
    required this.onToggleRow,
    required this.onToggleAll,
    required this.onRefresh,
    required this.onLoadMore,
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
  final Set<int> selectedIds;
  final int? hoveredId;
  final ValueChanged<int?> onHover;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;
  final ValueChanged<String?>? onGroupChanged;
  final ValueChanged<String> onSort;
  final VoidCallback onDirectionChanged;
  final VoidCallback onChooseColumns;
  final void Function(int id, bool selected) onToggleRow;
  final ValueChanged<bool> onToggleAll;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SurfaceHeader(
              palette: palette,
              data: data,
              compact: compact,
              onPeriodChanged: onPeriodChanged,
            ),
            if (data.loading) LinearProgressIndicator(color: palette.accent),
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
              onGroupChanged: onGroupChanged,
              onSort: onSort,
              onDirectionChanged: onDirectionChanged,
              onChooseColumns: onChooseColumns,
              onRefresh: onRefresh,
            ),
            _QueryStrip(palette: palette, data: data),
            Expanded(
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
                selectedIds: selectedIds,
                hoveredId: hoveredId,
                onHover: onHover,
                onSort: onSort,
                onToggleRow: onToggleRow,
                onToggleAll: onToggleAll,
              ),
            ),
            _TableFooter(
              palette: palette,
              data: data,
              selectedCount: selectedIds.length,
              onLoadMore: onLoadMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _SurfaceHeader extends StatelessWidget {
  const _SurfaceHeader({
    required this.palette,
    required this.data,
    required this.compact,
    required this.onPeriodChanged,
  });

  final _MatrixPalette palette;
  final UsersPageData data;
  final bool compact;
  final ValueChanged<UserDirectoryPeriod>? onPeriodChanged;

  static const _periods = [
    UserDirectoryPeriod.daily,
    UserDirectoryPeriod.weekly,
    UserDirectoryPeriod.monthly,
    UserDirectoryPeriod.quarterly,
    UserDirectoryPeriod.yearly,
    UserDirectoryPeriod.all,
  ];

  @override
  Widget build(BuildContext context) {
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${data.totalRows} ROWS · ${data.columns.length} PROPERTIES',
          style: TextStyle(
            color: palette.onDarkMuted,
            fontFamily: 'monospace',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Users / ${data.query.period.queryValue} activity',
          style: TextStyle(
            color: palette.onDark,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final periods = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: palette.onDark.withValues(alpha: .07),
          border: Border.all(color: palette.onDark.withValues(alpha: .1)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final period in _periods)
              _PeriodButton(
                period: period,
                active: data.query.period == period,
                palette: palette,
                onPressed: onPeriodChanged == null
                    ? null
                    : () => onPeriodChanged!(period),
              ),
          ],
        ),
      ),
    );

    return ColoredBox(
      color: palette.dark,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, compact ? 11 : 13, 16, 12),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [identity, const SizedBox(height: 10), periods],
              )
            : Row(
                children: [
                  Expanded(child: identity),
                  Flexible(child: periods),
                ],
              ),
      ),
    );
  }
}

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.period,
    required this.active,
    required this.palette,
    required this.onPressed,
  });

  final UserDirectoryPeriod period;
  final bool active;
  final _MatrixPalette palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    key: ValueKey('users-period-${period.queryValue}'),
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 29),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: active ? palette.accent : Colors.transparent,
      foregroundColor: active ? palette.accentInk : palette.onDarkMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
    ),
    child: Text(period.label),
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
    required this.onGroupChanged,
    required this.onSort,
    required this.onDirectionChanged,
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
  final ValueChanged<String?>? onGroupChanged;
  final ValueChanged<String> onSort;
  final VoidCallback onDirectionChanged;
  final VoidCallback onChooseColumns;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final search = SizedBox(
      height: 38,
      child: TextField(
        key: const ValueKey('users-search'),
        controller: searchController,
        focusNode: searchFocus,
        onChanged: onSearchChanged,
        onSubmitted: onSearchSubmitted,
        textInputAction: TextInputAction.search,
        style: TextStyle(color: palette.ink, fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.subtle,
          hintText: 'Search people',
          hintStyle: TextStyle(color: palette.faint),
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: DIcon(
              DIcons.magnifyingGlass,
              size: 15,
              color: palette.muted,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 37),
          suffixIcon: searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClearSearch,
                  icon: DIcon(DIcons.xmark, size: 13, color: palette.muted),
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
        _GroupMenu(
          palette: palette,
          groups: data.groupNames,
          selected: data.query.group,
          onChanged: onGroupChanged,
        ),
        const SizedBox(width: 7),
        _SortMenu(
          palette: palette,
          columns: data.columns,
          query: data.query,
          onSort: onSort,
        ),
        const SizedBox(width: 5),
        _ToolbarIconButton(
          key: const ValueKey('users-sort-direction'),
          palette: palette,
          tooltip: data.query.ascending ? 'Ascending' : 'Descending',
          onPressed: onDirectionChanged,
          icon: Transform.rotate(
            angle: data.query.ascending ? 0 : math.pi,
            child: DIcon(DIcons.arrowUp, size: 13, color: palette.ink),
          ),
        ),
        const SizedBox(width: 7),
        _ToolbarButton(
          key: const ValueKey('users-columns'),
          palette: palette,
          onPressed: onChooseColumns,
          icon: DIcons.list,
          label: 'Columns',
          count: visibleColumnCount,
        ),
        const SizedBox(width: 7),
        _ToolbarIconButton(
          key: const ValueKey('users-refresh'),
          palette: palette,
          tooltip: 'Refresh directory',
          onPressed: onRefresh == null ? null : () => unawaited(onRefresh!()),
          icon: DIcon(DIcons.arrowsRotate, size: 14, color: palette.ink),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
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
                const SizedBox(width: 10),
                controls,
              ],
            ),
    );
  }

  static OutlineInputBorder _inputBorder(
    _MatrixPalette palette, {
    bool focused = false,
  }) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(
      color: focused ? palette.green : palette.line,
      width: focused ? 1.5 : 1,
    ),
  );
}

const String _allGroups = '__all_groups__';

class _GroupMenu extends StatelessWidget {
  const _GroupMenu({
    required this.palette,
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  final _MatrixPalette palette;
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
        palette: palette,
        onPressed: openMenu,
        icon: DIcons.users,
        label: selected ?? 'All groups',
        chevron: true,
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({
    required this.palette,
    required this.columns,
    required this.query,
    required this.onSort,
  });

  final _MatrixPalette palette;
  final List<UserDirectoryColumn> columns;
  final UserDirectoryQuery query;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final labels = {
      'username': 'Username',
      for (final column in columns) column.name: column.label,
    };
    labels.putIfAbsent(query.order, () => _humanize(query.order));
    return ChoiceMenuAnchor<String>(
      title: 'Sort users',
      value: query.order,
      options: [
        for (final entry in labels.entries)
          ChoiceMenuOption(
            value: entry.key,
            title: entry.value,
            description: 'Order the directory by ${entry.value.toLowerCase()}',
          ),
      ],
      onSelected: onSort,
      builder: (context, openMenu) => _ToolbarButton(
        key: const ValueKey('users-sort'),
        palette: palette,
        onPressed: openMenu,
        icon: DIcons.arrowUp,
        label: labels[query.order]!,
        chevron: true,
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    super.key,
    required this.palette,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.count,
    this.chevron = false,
  });

  final _MatrixPalette palette;
  final VoidCallback? onPressed;
  final DIconData icon;
  final String label;
  final int? count;
  final bool chevron;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      maximumSize: const Size(190, 38),
      padding: const EdgeInsets.symmetric(horizontal: 11),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: palette.subtle,
      foregroundColor: palette.ink,
      side: BorderSide(color: palette.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DIcon(icon, size: 13, color: palette.muted),
        const SizedBox(width: 7),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (count != null) ...[
          const SizedBox(width: 7),
          Container(
            constraints: const BoxConstraints(minWidth: 18),
            height: 18,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              '$count',
              style: TextStyle(color: palette.accentInk, fontSize: 8),
            ),
          ),
        ],
        if (chevron) ...[
          const SizedBox(width: 7),
          DIcon(DIcons.chevronDown, size: 10, color: palette.faint),
        ],
      ],
    ),
  );
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final _MatrixPalette palette;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      fixedSize: const Size(38, 38),
      minimumSize: const Size(38, 38),
      maximumSize: const Size(38, 38),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: palette.subtle,
      side: BorderSide(color: palette.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    icon: icon,
  );
}

class _QueryStrip extends StatelessWidget {
  const _QueryStrip({required this.palette, required this.data});

  final _MatrixPalette palette;
  final UsersPageData data;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 7),
      children: [
        _QueryChip(
          palette: palette,
          property: 'Period',
          value: data.query.period.label,
        ),
        const SizedBox(width: 6),
        if (data.query.group case final group?) ...[
          _QueryChip(palette: palette, property: 'Group', value: group),
          const SizedBox(width: 6),
        ],
        if (data.query.search.isNotEmpty) ...[
          _QueryChip(
            palette: palette,
            property: 'Search',
            value: data.query.search,
          ),
          const SizedBox(width: 6),
        ],
        _QueryChip(
          palette: palette,
          property: 'Sort',
          value:
              '${_humanize(data.query.order)} '
              '${data.query.ascending ? '↑' : '↓'}',
        ),
        const SizedBox(width: 12),
        Center(
          child: Text(
            data.loaded ? '${data.totalRows} results' : 'Loading dataset…',
            style: TextStyle(
              color: palette.faint,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
          ),
        ),
      ],
    ),
  );
}

class _QueryChip extends StatelessWidget {
  const _QueryChip({
    required this.palette,
    required this.property,
    required this.value,
  });

  final _MatrixPalette palette;
  final String property;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    height: 25,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: palette.accentSoft,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          property.toUpperCase(),
          style: TextStyle(
            color: palette.green,
            fontSize: 7,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: palette.accentInk,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
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
    required this.selectedIds,
    required this.hoveredId,
    required this.onHover,
    required this.onSort,
    required this.onToggleRow,
    required this.onToggleAll,
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
  final Set<int> selectedIds;
  final int? hoveredId;
  final ValueChanged<int?> onHover;
  final ValueChanged<String> onSort;
  final void Function(int id, bool selected) onToggleRow;
  final ValueChanged<bool> onToggleAll;

  @override
  Widget build(BuildContext context) {
    if (!data.loaded && data.items.isEmpty) {
      return _TableState(
        key: const ValueKey('users-loading'),
        palette: palette,
        icon: DIcons.users,
        title: 'Reading community signal',
        detail: 'Loading people and directory properties…',
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

    final allSelected = data.items.every(
      (item) => selectedIds.contains(item.id),
    );
    final someSelected = selectedIds.isNotEmpty && !allSelected;
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
                      checked: allSelected
                          ? true
                          : someSelected
                          ? null
                          : false,
                      ascending:
                          data.query.order == 'username' &&
                          data.query.ascending,
                      sorted: data.query.order == 'username',
                      onToggleAll: onToggleAll,
                      onSort: () => onSort('username'),
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: const PageStorageKey('users-identity-scroll'),
                        controller: identityVertical,
                        itemExtent: rowHeight,
                        itemCount: data.items.length,
                        itemBuilder: (context, index) {
                          final item = data.items[index];
                          return _IdentityRow(
                            key: ValueKey('user-row-${item.user.username}'),
                            palette: palette,
                            item: item,
                            siteUrl: siteUrl,
                            rank: index + 1,
                            selected: selectedIds.contains(item.id),
                            hovered: hoveredId == item.id,
                            onHover: onHover,
                            onSelected: (value) => onToggleRow(item.id, value),
                          );
                        },
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
                                            style: TextStyle(
                                              color: palette.faint,
                                              fontSize: 10,
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
                                  child: ListView.builder(
                                    key: const PageStorageKey(
                                      'users-metrics-scroll',
                                    ),
                                    controller: metricsVertical,
                                    itemExtent: rowHeight,
                                    itemCount: data.items.length,
                                    itemBuilder: (context, index) {
                                      final item = data.items[index];
                                      return MouseRegion(
                                        onEnter: (_) => onHover(item.id),
                                        onExit: (_) => onHover(null),
                                        child: ColoredBox(
                                          color: _rowColor(
                                            palette,
                                            selected: selectedIds.contains(
                                              item.id,
                                            ),
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
                                                        maxima[column.id] ?? 0,
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
    required this.checked,
    required this.ascending,
    required this.sorted,
    required this.onToggleAll,
    required this.onSort,
  });

  final _MatrixPalette palette;
  final double height;
  final bool? checked;
  final bool ascending;
  final bool sorted;
  final ValueChanged<bool> onToggleAll;
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
    child: Row(
      children: [
        SizedBox(
          width: 38,
          child: Transform.scale(
            scale: .82,
            child: Checkbox(
              key: const ValueKey('users-select-all'),
              value: checked,
              tristate: true,
              activeColor: palette.green,
              onChanged: (value) => onToggleAll(value ?? true),
            ),
          ),
        ),
        const SizedBox(width: 29),
        Expanded(
          child: _HeaderButton(
            label: 'User',
            sorted: sorted,
            ascending: ascending,
            palette: palette,
            onPressed: onSort,
            alignment: Alignment.centerLeft,
          ),
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
  Widget build(BuildContext context) => Semantics(
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
                label.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: alignment == Alignment.centerRight
                    ? TextAlign.right
                    : TextAlign.left,
                style: TextStyle(
                  color: sorted ? palette.ink : palette.faint,
                  fontFamily: 'monospace',
                  fontSize: 7.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .55,
                ),
              ),
            ),
            if (sorted) ...[
              const SizedBox(width: 4),
              Transform.rotate(
                angle: ascending ? 0 : math.pi,
                child: DIcon(DIcons.arrowUp, size: 8, color: palette.green),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    super.key,
    required this.palette,
    required this.item,
    required this.siteUrl,
    required this.rank,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onSelected,
  });

  final _MatrixPalette palette;
  final UserDirectoryItem item;
  final String siteUrl;
  final int rank;
  final bool selected;
  final bool hovered;
  final ValueChanged<int?> onHover;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => onHover(item.id),
    onExit: (_) => onHover(null),
    child: Container(
      decoration: BoxDecoration(
        color: _rowColor(palette, selected: selected, hovered: hovered),
        border: Border(
          right: BorderSide(color: palette.line),
          bottom: BorderSide(color: palette.rowLine),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Transform.scale(
              scale: .78,
              child: Checkbox(
                key: ValueKey('user-select-${item.user.username}'),
                value: selected,
                activeColor: palette.green,
                onChanged: (value) => onSelected(value ?? false),
              ),
            ),
          ),
          SizedBox(
            width: 29,
            child: Center(
              child: Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank <= 3 ? palette.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank <= 3 ? palette.accentInk : palette.faint,
                    fontFamily: 'monospace',
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: UserCardTarget(
                username: item.user.username,
                siteUrl: siteUrl.isEmpty ? null : siteUrl,
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
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
                                  style: TextStyle(
                                    color: palette.ink,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
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
                                    group.toUpperCase(),
                                    style: TextStyle(
                                      color: palette.green,
                                      fontSize: 6,
                                      fontWeight: FontWeight.w800,
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
                            style: TextStyle(color: palette.faint, fontSize: 8),
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
      style: TextStyle(
        color: palette.dark,
        fontSize: 8,
        fontWeight: FontWeight.w900,
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
              style: TextStyle(
                color: palette.ink,
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: numeric == null ? FontWeight.w500 : FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableFooter extends StatelessWidget {
  const _TableFooter({
    required this.palette,
    required this.data,
    required this.selectedCount,
    required this.onLoadMore,
  });

  final _MatrixPalette palette;
  final UsersPageData data;
  final int selectedCount;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 45),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: palette.subtle,
      border: Border(top: BorderSide(color: palette.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            selectedCount > 0
                ? '$selectedCount selected'
                : '${data.items.length} of ${data.totalRows} loaded',
            style: TextStyle(
              color: palette.muted,
              fontFamily: 'monospace',
              fontSize: 9,
            ),
          ),
        ),
        if (data.pageError && data.error != null)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              data.error!,
              style: TextStyle(color: palette.danger, fontSize: 9),
            ),
          ),
        if (data.loadingMore)
          SizedBox(
            width: 26,
            height: 26,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.green,
              ),
            ),
          )
        else if (data.hasMore || data.pageError)
          FilledButton(
            key: const ValueKey('users-load-more'),
            onPressed: onLoadMore,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: palette.accent,
              foregroundColor: palette.accentInk,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              textStyle: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(data.pageError ? 'Retry' : 'Load 50 more'),
          ),
      ],
    ),
  );
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
            style: TextStyle(
              color: palette.ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 11),
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
    required this.canvas,
    required this.surface,
    required this.subtle,
    required this.heroCard,
    required this.tableHeader,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.rowLine,
    required this.dark,
    required this.onDark,
    required this.onDarkMuted,
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.green,
    required this.danger,
    required this.shadow,
  });

  factory _MatrixPalette.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? const _MatrixPalette(
            canvas: Color(0xFF101713),
            surface: Color(0xFF17201A),
            subtle: Color(0xFF1D2921),
            heroCard: Color(0xFF17221B),
            tableHeader: Color(0xFF1D2921),
            ink: Color(0xFFF0F7F1),
            muted: Color(0xFFA7B4AA),
            faint: Color(0xFF748178),
            line: Color(0xFF304036),
            rowLine: Color(0xFF26352C),
            dark: Color(0xFF09110D),
            onDark: Color(0xFFF6FFF9),
            onDarkMuted: Color(0xFF819087),
            accent: Color(0xFFA7EF4C),
            accentInk: Color(0xFF152708),
            accentSoft: Color(0xFF29421D),
            green: Color(0xFF7BD6A8),
            danger: Color(0xFFFF8F86),
            shadow: Color(0x40000000),
          )
        : const _MatrixPalette(
            canvas: Color(0xFFDFE6DF),
            surface: Color(0xFFFFFFFF),
            subtle: Color(0xFFEDF2ED),
            heroCard: Color(0xB3F7FAF6),
            tableHeader: Color(0xFFEDF2ED),
            ink: Color(0xFF132019),
            muted: Color(0xFF657169),
            faint: Color(0xFF94A198),
            line: Color(0xFFD4DED5),
            rowLine: Color(0xFFEDF1ED),
            dark: Color(0xFF14231C),
            onDark: Color(0xFFF6FFF9),
            onDarkMuted: Color(0xFF829088),
            accent: Color(0xFFA7EF4C),
            accentInk: Color(0xFF152708),
            accentSoft: Color(0xFFDFFFB7),
            green: Color(0xFF338F69),
            danger: Color(0xFFB83C34),
            shadow: Color(0x1A142C1F),
          );
  }

  final Color canvas;
  final Color surface;
  final Color subtle;
  final Color heroCard;
  final Color tableHeader;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;
  final Color rowLine;
  final Color dark;
  final Color onDark;
  final Color onDarkMuted;
  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color green;
  final Color danger;
  final Color shadow;

  Color avatarFor(int id) {
    const colors = [
      Color(0xFFFFD39A),
      Color(0xFF9FE2DD),
      Color(0xFFFFB8CE),
      Color(0xFFFFE083),
      Color(0xFFADD7FF),
      Color(0xFFD6EF93),
    ];
    return colors[id.abs() % colors.length];
  }
}

Color _rowColor(
  _MatrixPalette palette, {
  required bool selected,
  required bool hovered,
}) {
  if (selected) return palette.accentSoft.withValues(alpha: .58);
  if (hovered) return palette.accentSoft.withValues(alpha: .28);
  return palette.surface;
}

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

String _formatUpdated(DateTime? value) {
  if (value == null) return 'Pending';
  return DateFormat.MMMd().add_Hm().format(value.toLocal());
}

String _humanize(String value) {
  final words = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (words.isEmpty) return value;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

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
