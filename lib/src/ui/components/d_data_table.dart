import 'dart:math' as math;

import 'package:discourse_native/src/theme/discourse_typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';
import 'd_checkbox.dart';
import 'd_dropdown_menu.dart';
import 'd_input.dart';
import 'd_pagination.dart';
import 'd_popover.dart';
import 'd_resizable.dart';
import 'd_select.dart';
import 'd_table.dart';

enum DDataTableSortDirection { ascending, descending }

enum DDataTableOperationMode {
  /// Filtering, sorting and pagination are derived from the complete [DDataTable.data].
  local,

  /// [DDataTable.data] is already prepared by the caller, normally one server page.
  manual,
}

@immutable
class DDataTableSort {
  const DDataTableSort({required this.columnId, required this.direction});

  final String columnId;
  final DDataTableSortDirection direction;

  @override
  bool operator ==(Object other) =>
      other is DDataTableSort &&
      other.columnId == columnId &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(columnId, direction);
}

const _absent = Object();

/// Presentation state shared by local and server-controlled data tables.
///
/// Page numbers are one-based. Row IDs and column IDs remain stable when rows
/// are reordered, filtered, paginated or replaced. Unknown IDs are ignored by
/// the renderer; a local table also prunes selection for rows that no longer
/// exist in its complete dataset.
@immutable
class DDataTableState {
  DDataTableState({
    this.sort,
    Map<String, String> filters = const {},
    Set<String> hiddenColumnIds = const {},
    Set<Object> selectedRowIds = const {},
    this.page = 1,
    this.pageSize = 10,
  }) : assert(page > 0),
       assert(pageSize > 0),
       filters = Map.unmodifiable(filters),
       hiddenColumnIds = Set.unmodifiable(hiddenColumnIds),
       selectedRowIds = Set.unmodifiable(selectedRowIds);

  final DDataTableSort? sort;
  final Map<String, String> filters;
  final Set<String> hiddenColumnIds;
  final Set<Object> selectedRowIds;
  final int page;
  final int pageSize;

  DDataTableState copyWith({
    Object? sort = _absent,
    Map<String, String>? filters,
    Set<String>? hiddenColumnIds,
    Set<Object>? selectedRowIds,
    int? page,
    int? pageSize,
  }) => DDataTableState(
    sort: identical(sort, _absent) ? this.sort : sort as DDataTableSort?,
    filters: filters ?? this.filters,
    hiddenColumnIds: hiddenColumnIds ?? this.hiddenColumnIds,
    selectedRowIds: selectedRowIds ?? this.selectedRowIds,
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
  );

  @override
  bool operator ==(Object other) =>
      other is DDataTableState &&
      other.sort == sort &&
      mapEquals(other.filters, filters) &&
      setEquals(other.hiddenColumnIds, hiddenColumnIds) &&
      setEquals(other.selectedRowIds, selectedRowIds) &&
      other.page == page &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(
    sort,
    Object.hashAllUnordered(
      filters.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(hiddenColumnIds),
    Object.hashAllUnordered(selectedRowIds),
    page,
    pageSize,
  );
}

/// Optional borrowed state owner for composing filters, view options and paging
/// outside [DDataTable]. The widget never disposes a borrowed controller.
class DDataTableController extends ChangeNotifier {
  DDataTableController({DDataTableState? initialState})
    : _value = initialState ?? DDataTableState();

  DDataTableState _value;

  DDataTableState get value => _value;
  set value(DDataTableState next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  void setFilter(String columnId, String value) {
    final filters = Map<String, String>.of(_value.filters);
    final normalized = value.trim();
    if (normalized.isEmpty) {
      filters.remove(columnId);
    } else {
      filters[columnId] = value;
    }
    this.value = _value.copyWith(filters: filters, page: 1);
  }

  void setSort(String columnId, DDataTableSortDirection? direction) {
    value = _value.copyWith(
      sort: direction == null
          ? null
          : DDataTableSort(columnId: columnId, direction: direction),
      page: 1,
    );
  }

  void setColumnVisible(String columnId, bool visible) {
    final hidden = Set<String>.of(_value.hiddenColumnIds);
    visible ? hidden.remove(columnId) : hidden.add(columnId);
    value = _value.copyWith(hiddenColumnIds: hidden, page: 1);
  }

  void setRowSelected(Object rowId, bool selected) {
    final selection = Set<Object>.of(_value.selectedRowIds);
    selected ? selection.add(rowId) : selection.remove(rowId);
    value = _value.copyWith(selectedRowIds: selection);
  }

  void setPageRowsSelected(Iterable<Object> rowIds, bool selected) {
    final selection = Set<Object>.of(_value.selectedRowIds);
    selected ? selection.addAll(rowIds) : selection.removeAll(rowIds);
    value = _value.copyWith(selectedRowIds: selection);
  }

  void setPage(int page) => value = _value.copyWith(page: math.max(1, page));

  void setPageSize(int pageSize) {
    if (pageSize <= 0) throw ArgumentError.value(pageSize, 'pageSize');
    final firstVisibleItem = (_value.page - 1) * _value.pageSize;
    value = _value.copyWith(
      pageSize: pageSize,
      page: firstVisibleItem ~/ pageSize + 1,
    );
  }
}

typedef DDataTableCellBuilder<T> =
    Widget Function(BuildContext context, DDataTableCellContext<T> cell);
typedef DDataTableHeaderBuilder<T> =
    Widget Function(BuildContext context, DDataTableHeaderContext<T> header);
typedef DDataTableRowId<T> = Object Function(T row);
typedef DDataTableComparator<T> = int Function(T first, T second);
typedef DDataTableFilter<T> = bool Function(T row, String query);

@immutable
class DDataTableColumn<T> {
  const DDataTableColumn({
    required this.id,
    required this.label,
    required this.cellBuilder,
    this.headerBuilder,
    this.compare,
    this.filter,
    this.filterText,
    this.hideable = true,
    this.initiallyHidden = false,
    this.width,
    this.resizable = false,
    this.minWidth = 64,
    this.maxWidth = 800,
    this.alignment = AlignmentDirectional.centerStart,
    this.headerAlignment = AlignmentDirectional.centerStart,
    this.padding = const EdgeInsets.all(8),
    this.headerPadding = const EdgeInsets.symmetric(horizontal: 8),
  }) : assert(id != ''),
       assert(minWidth > 0),
       assert(maxWidth >= minWidth);

  final String id;
  final String label;
  final DDataTableCellBuilder<T> cellBuilder;
  final DDataTableHeaderBuilder<T>? headerBuilder;
  final DDataTableComparator<T>? compare;
  final DDataTableFilter<T>? filter;
  final String Function(T row)? filterText;
  final bool hideable;
  final bool initiallyHidden;
  final TableColumnWidth? width;

  /// Adds an accessible pointer/keyboard resize handle to this header.
  final bool resizable;
  final double minWidth;
  final double maxWidth;
  final AlignmentGeometry alignment;
  final AlignmentGeometry headerAlignment;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry headerPadding;

  bool get sortable => compare != null;
  bool get filterable => filter != null || filterText != null;

  bool matches(T row, String query) =>
      filter?.call(row, query) ??
      (filterText?.call(row).toLowerCase().contains(query.toLowerCase()) ??
          true);
}

@immutable
class DDataTableCellContext<T> {
  const DDataTableCellContext({
    required this.row,
    required this.rowId,
    required this.index,
    required this.selected,
    required this.onSelectedChanged,
  });

  final T row;
  final Object rowId;
  final int index;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
}

@immutable
class DDataTableHeaderContext<T> {
  const DDataTableHeaderContext({
    required this.column,
    required this.sortDirection,
    required this.onSortChanged,
    required this.onVisibilityChanged,
  });

  final DDataTableColumn<T> column;
  final DDataTableSortDirection? sortDirection;
  final ValueChanged<DDataTableSortDirection?>? onSortChanged;
  final ValueChanged<bool>? onVisibilityChanged;
}

@immutable
class DDataTableMetrics {
  const DDataTableMetrics({
    required this.state,
    required this.pageCount,
    required this.filteredRowCount,
    required this.selectedFilteredRowCount,
  });

  final DDataTableState state;
  final int pageCount;
  final int filteredRowCount;
  final int selectedFilteredRowCount;
}

typedef DDataTableFooterBuilder =
    Widget Function(BuildContext context, DDataTableMetrics metrics);

@immutable
class _DDataTableView<T> {
  const _DDataTableView({required this.pageRows, required this.metrics});

  final List<T> pageRows;
  final DDataTableMetrics metrics;
}

/// A headless-friendly typed data table built from the shadcn Table primitives.
///
/// Supply either [controller], or [state] with [onStateChanged], or neither for
/// local owned state. In [DDataTableOperationMode.manual], callers perform data
/// operations and pass the prepared page plus [rowCount]/[pageCount]; loading,
/// errors, requests and caching remain outside this generic widget.
class DDataTable<T> extends StatefulWidget {
  const DDataTable({
    super.key,
    required this.data,
    required this.columns,
    required this.rowId,
    this.controller,
    this.state,
    this.onStateChanged,
    this.operationMode = DDataTableOperationMode.local,
    this.rowCount,
    this.pageCount,
    this.selectedFilteredRowCount,
    this.selectable = false,
    this.selectionEnabled,
    this.selectionColumnLabel = 'Select',
    this.selectAllLabel = 'Select all rows on this page',
    this.selectRowLabel,
    this.empty = const Text('No results.'),
    this.semanticLabel,
    this.minimumWidth = 0,
    this.scrollController,
    this.footerBuilder,
    this.columnWidths = const {},
    this.onColumnWidthsChanged,
    this.onColumnResizeEnd,
    this.onColumnResizeStart,
    this.virtualized = false,
    this.verticalScrollController,
  }) : assert(controller == null || state == null),
       assert(state == null || onStateChanged != null),
       assert(rowCount == null || rowCount >= 0),
       assert(pageCount == null || pageCount >= 0),
       assert(
         selectedFilteredRowCount == null || selectedFilteredRowCount >= 0,
       ),
       assert(minimumWidth >= 0);

  final List<T> data;
  final List<DDataTableColumn<T>> columns;
  final DDataTableRowId<T> rowId;
  final DDataTableController? controller;
  final DDataTableState? state;
  final ValueChanged<DDataTableState>? onStateChanged;
  final DDataTableOperationMode operationMode;
  final int? rowCount;
  final int? pageCount;
  final int? selectedFilteredRowCount;
  final bool selectable;
  final bool Function(T row)? selectionEnabled;
  final String selectionColumnLabel;
  final String selectAllLabel;
  final String Function(T row)? selectRowLabel;
  final Widget empty;
  final String? semanticLabel;
  final double minimumWidth;
  final ScrollController? scrollController;
  final DDataTableFooterBuilder? footerBuilder;

  /// Pixel widths keyed by stable column ID. Persist these in the app adapter.
  final Map<String, double> columnWidths;
  final ValueChanged<Map<String, double>>? onColumnWidthsChanged;
  final VoidCallback? onColumnResizeEnd;
  final VoidCallback? onColumnResizeStart;

  /// Lazily builds body rows with natural heights under a stationary header.
  /// Requires bounded height. Unspecified column widths default to 160 pixels.
  /// The native scroll viewport exposes lazy rows as accessible groups;
  /// cells retain their controls and header labels. Eager mode uses table roles.
  final bool virtualized;
  final ScrollController? verticalScrollController;
  @override
  State<DDataTable<T>> createState() => _DDataTableState<T>();
}

class _DDataTableState<T> extends State<DDataTable<T>> {
  late DDataTableState _ownedState = _defaultState();
  bool _normalizationScheduled = false;
  final Map<String, double> _resizedWidths = {};

  DDataTableState _defaultState() => DDataTableState(
    hiddenColumnIds: {
      for (final column in widget.columns)
        if (column.initiallyHidden && column.hideable) column.id,
    },
  );

  DDataTableState get _sourceState =>
      widget.state ?? widget.controller?.value ?? _ownedState;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(DDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.columnWidths, widget.columnWidths)) {
      _resizedWidths.clear();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_controllerChanged);
      widget.controller?.addListener(_controllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  void _request(DDataTableState next) {
    if (widget.state != null) {
      widget.onStateChanged?.call(next);
    } else if (widget.controller != null) {
      widget.controller!.value = next;
    } else {
      setState(() => _ownedState = next);
      widget.onStateChanged?.call(next);
    }
  }

  void _scheduleNormalization(DDataTableState normalized) {
    if (_normalizationScheduled) return;
    _normalizationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _normalizationScheduled = false;
      if (!mounted) return;
      final current = _sourceState;
      final latest = _normalized(current);
      if (latest != current) _request(latest);
    });
  }

  DDataTableState _normalized(DDataTableState source) {
    final ids = <String>{};
    final byId = <String, DDataTableColumn<T>>{};
    for (final column in widget.columns) {
      assert(ids.add(column.id), 'Data table column IDs must be unique.');
      byId[column.id] = column;
    }
    final rowIds = <Object>{};
    for (final row in widget.data) {
      assert(
        rowIds.add(widget.rowId(row)),
        'Data table row IDs must be unique.',
      );
    }
    final sort = source.sort;
    final normalizedSort = sort != null && byId[sort.columnId]?.sortable == true
        ? sort
        : null;
    final filters = <String, String>{
      for (final entry in source.filters.entries)
        if (entry.value.trim().isNotEmpty &&
            byId[entry.key]?.filterable == true)
          entry.key: entry.value,
    };
    final hidden = <String>{
      for (final id in source.hiddenColumnIds)
        if (byId[id]?.hideable == true) id,
    };
    final selection = widget.operationMode == DDataTableOperationMode.local
        ? source.selectedRowIds.intersection(rowIds)
        : source.selectedRowIds;
    final effectiveRows = widget.operationMode == DDataTableOperationMode.local
        ? _filtered(widget.data, filters)
        : widget.data;
    final count = widget.operationMode == DDataTableOperationMode.local
        ? effectiveRows.length
        : (widget.rowCount ?? widget.data.length);
    final computedPages = count == 0 ? 1 : (count / source.pageSize).ceil();
    final pages = math.max(1, widget.pageCount ?? computedPages);
    return source.copyWith(
      sort: normalizedSort,
      filters: filters,
      hiddenColumnIds: hidden,
      selectedRowIds: selection,
      page: source.page.clamp(1, pages).toInt(),
    );
  }

  List<T> _filtered(List<T> rows, Map<String, String> filters) {
    if (filters.isEmpty) return List<T>.of(rows);
    final byId = {for (final column in widget.columns) column.id: column};
    return [
      for (final row in rows)
        if (filters.entries.every(
          (entry) => byId[entry.key]!.matches(row, entry.value),
        ))
          row,
    ];
  }

  _DDataTableView<T> _view(DDataTableState state) {
    if (widget.operationMode == DDataTableOperationMode.manual) {
      final count = widget.rowCount ?? widget.data.length;
      final pages =
          widget.pageCount ??
          (count == 0 ? 0 : (count / state.pageSize).ceil());
      return _DDataTableView(
        pageRows: List.unmodifiable(widget.data),
        metrics: DDataTableMetrics(
          state: state,
          pageCount: pages,
          filteredRowCount: count,
          selectedFilteredRowCount:
              widget.selectedFilteredRowCount ?? state.selectedRowIds.length,
        ),
      );
    }
    final filtered = _filtered(widget.data, state.filters);
    var sorted = List<T>.of(filtered);
    final sort = state.sort;
    if (sort != null) {
      final column = widget.columns.firstWhere((c) => c.id == sort.columnId);
      final indexed = sorted.indexed.toList();
      indexed.sort((first, second) {
        final result = column.compare!(first.$2, second.$2);
        final directed = sort.direction == DDataTableSortDirection.ascending
            ? result
            : -result;
        return directed == 0 ? first.$1.compareTo(second.$1) : directed;
      });
      sorted = [for (final entry in indexed) entry.$2];
    }
    final pages = sorted.isEmpty ? 0 : (sorted.length / state.pageSize).ceil();
    final start = math.min((state.page - 1) * state.pageSize, sorted.length);
    final end = math.min(start + state.pageSize, sorted.length);
    return _DDataTableView(
      pageRows: List.unmodifiable(sorted.sublist(start, end)),
      metrics: DDataTableMetrics(
        state: state,
        pageCount: pages,
        filteredRowCount: sorted.length,
        selectedFilteredRowCount: sorted
            .map(widget.rowId)
            .where(state.selectedRowIds.contains)
            .length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final sourceState = _sourceState;
    final state = _normalized(sourceState);
    if (state != sourceState) _scheduleNormalization(state);
    final view = _view(state);
    final visible = [
      for (final column in widget.columns)
        if (!state.hiddenColumnIds.contains(column.id)) column,
    ];
    final selectableRows = [
      for (final row in view.pageRows)
        if (widget.selectionEnabled?.call(row) ?? true) widget.rowId(row),
    ];
    final selectedOnPage = selectableRows
        .where(state.selectedRowIds.contains)
        .length;
    final allPageSelected =
        selectableRows.isNotEmpty && selectedOnPage == selectableRows.length;
    final somePageSelected = selectedOnPage > 0 && !allPageSelected;

    void change(DDataTableState next) => _request(_normalized(next));

    final columnWidths = <int, TableColumnWidth>{};
    var offset = 0;
    if (widget.selectable) {
      columnWidths[0] = const FixedColumnWidth(48);
      offset = 1;
    }
    for (var index = 0; index < visible.length; index++) {
      final column = visible[index];
      final width =
          widget.virtualized ||
              column.resizable ||
              widget.columnWidths.containsKey(column.id)
          ? FixedColumnWidth(_columnWidth(column))
          : column.width;
      if (width != null) columnWidths[index + offset] = width;
    }

    final rowIndices = widget.virtualized
        ? {
            for (var index = 0; index < view.pageRows.length; index++)
              ValueKey(widget.rowId(view.pageRows[index])): index,
          }
        : const <Key, int>{};
    final table = ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius * .8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radius * .8),
        ),
        child: DTable(
          semanticLabel: widget.semanticLabel,
          rowBuilder: widget.virtualized && view.pageRows.isNotEmpty
              ? (context, index) => _row(
                  context,
                  view.pageRows[index],
                  index,
                  visible,
                  state,
                  change,
                )
              : widget.virtualized
              ? (context, index) => throw StateError('Empty table')
              : null,
          rowCount: view.pageRows.length,
          findChildIndexCallback: widget.virtualized
              ? (key) => rowIndices[key]
              : null,
          verticalScrollController: widget.verticalScrollController,
          minimumWidth: widget.minimumWidth,
          controller: widget.scrollController,
          columnWidths: columnWidths,
          header: DTableHeader(
            rows: [
              DTableRow(
                cells: [
                  if (!widget.selectable && visible.isEmpty)
                    const DTableHead(child: SizedBox.shrink()),
                  if (widget.selectable)
                    DTableHead(
                      padding: EdgeInsets.zero,
                      child: Semantics(
                        container: true,
                        explicitChildNodes: true,
                        label: widget.selectionColumnLabel,
                        child: DCheckbox(
                          value: allPageSelected
                              ? true
                              : somePageSelected
                              ? null
                              : false,
                          tristate: true,
                          enabled: selectableRows.isNotEmpty,
                          semanticLabel: widget.selectAllLabel,
                          onChanged: selectableRows.isEmpty
                              ? null
                              : (selected) => change(
                                  state.copyWith(
                                    selectedRowIds: selected == true
                                        ? ({
                                            ...state.selectedRowIds,
                                            ...selectableRows,
                                          })
                                        : (Set<Object>.of(state.selectedRowIds)
                                            ..removeAll(selectableRows)),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  for (final column in visible)
                    DTableHead(
                      alignment: column.headerAlignment,
                      padding: EdgeInsets.zero,
                      child: _resizableHeader(
                        column,
                        column.headerBuilder?.call(
                              context,
                              DDataTableHeaderContext(
                                column: column,
                                sortDirection: state.sort?.columnId == column.id
                                    ? state.sort!.direction
                                    : null,
                                onSortChanged: column.sortable
                                    ? (direction) => change(
                                        state.copyWith(
                                          sort: direction == null
                                              ? null
                                              : DDataTableSort(
                                                  columnId: column.id,
                                                  direction: direction,
                                                ),
                                          page: 1,
                                        ),
                                      )
                                    : null,
                                onVisibilityChanged: column.hideable
                                    ? (visible) {
                                        final hidden = Set<String>.of(
                                          state.hiddenColumnIds,
                                        );
                                        visible
                                            ? hidden.remove(column.id)
                                            : hidden.add(column.id);
                                        change(
                                          state.copyWith(
                                            hiddenColumnIds: hidden,
                                            page: 1,
                                          ),
                                        );
                                      }
                                    : null,
                              ),
                            ) ??
                            Text(column.label),
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: DTableBody(
            rows: view.pageRows.isEmpty
                ? [
                    DTableRow(
                      cells: [
                        DTableCell(
                          columnSpan: math.max(
                            1,
                            visible.length + (widget.selectable ? 1 : 0),
                          ),
                          alignment: Alignment.center,
                          child: SizedBox(
                            height: 80,
                            child: Center(child: widget.empty),
                          ),
                        ),
                      ],
                    ),
                  ]
                : widget.virtualized
                ? const []
                : [
                    for (var index = 0; index < view.pageRows.length; index++)
                      _row(
                        context,
                        view.pageRows[index],
                        index,
                        visible,
                        state,
                        change,
                      ),
                  ],
          ),
        ),
      ),
    );
    final footerBuilder = widget.footerBuilder;
    if (footerBuilder == null) return table;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.virtualized) Expanded(child: table) else table,
        footerBuilder(context, view.metrics),
      ],
    );
  }

  double _columnWidth(DDataTableColumn<T> column) {
    final initial = column.width;
    final value =
        widget.columnWidths[column.id] ??
        _resizedWidths[column.id] ??
        (initial is FixedColumnWidth ? initial.value : 160.0);
    return (value.isFinite ? value : column.minWidth).clamp(
      column.minWidth,
      column.maxWidth,
    );
  }

  Widget _resizableHeader(DDataTableColumn<T> column, Widget child) {
    final padded = Padding(padding: column.headerPadding, child: child);
    if (!column.resizable) return padded;
    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: padded,
          ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: DResizableHandle.resolveHitExtent(context, 24),
            child: DResizableHandle.standalone(
              semanticLabel: 'Resize ${column.label} column',
              value: _columnWidth(column),
              min: column.minWidth,
              max: column.maxWidth,
              dividerAlignment: AlignmentDirectional.centerEnd,
              onChanged: (width) {
                setState(() => _resizedWidths[column.id] = width);
                widget.onColumnWidthsChanged?.call(
                  Map.unmodifiable({...widget.columnWidths, ..._resizedWidths}),
                );
              },
              onChangeEnd: widget.onColumnResizeEnd,
              onChangeStart: widget.onColumnResizeStart,
            ),
          ),
        ],
      ),
    );
  }

  DTableRow _row(
    BuildContext context,
    T row,
    int index,
    List<DDataTableColumn<T>> columns,
    DDataTableState state,
    ValueChanged<DDataTableState> change,
  ) {
    final id = widget.rowId(row);
    final selected = state.selectedRowIds.contains(id);
    final enabled = widget.selectionEnabled?.call(row) ?? true;

    void select(bool value) {
      final selection = Set<Object>.of(state.selectedRowIds);
      value ? selection.add(id) : selection.remove(id);
      change(state.copyWith(selectedRowIds: selection));
    }

    final cell = DDataTableCellContext<T>(
      row: row,
      rowId: id,
      index: index,
      selected: selected,
      onSelectedChanged: widget.selectable && enabled ? select : null,
    );
    return DTableRow(
      key: ValueKey(id),
      selected: selected,
      cells: [
        if (!widget.selectable && columns.isEmpty)
          const DTableCell(child: SizedBox.shrink()),
        if (widget.selectable)
          DTableCell(
            padding: EdgeInsets.zero,
            child: DCheckbox(
              value: selected,
              enabled: enabled,
              semanticLabel:
                  widget.selectRowLabel?.call(row) ?? 'Select row ${index + 1}',
              onChanged: enabled ? (value) => select(value == true) : null,
            ),
          ),
        for (final column in columns)
          DTableCell(
            alignment: column.alignment,
            padding: column.padding,
            child: column.cellBuilder(context, cell),
          ),
      ],
    );
  }
}

/// Reusable sortable/hideable header from the official tasks composition.
class DDataTableColumnHeader extends StatelessWidget {
  const DDataTableColumnHeader({
    super.key,
    required this.title,
    this.sortDirection,
    this.onSortChanged,
    this.onHide,
    this.ascendingLabel = 'Sort ascending',
    this.descendingLabel = 'Sort descending',
    this.hideLabel = 'Hide column',
  });

  final String title;
  final DDataTableSortDirection? sortDirection;
  final ValueChanged<DDataTableSortDirection?>? onSortChanged;
  final VoidCallback? onHide;
  final String ascendingLabel;
  final String descendingLabel;
  final String hideLabel;

  @override
  Widget build(BuildContext context) {
    if (onSortChanged == null && onHide == null) return Text(title);
    return DDropdownMenu(
      content: DDropdownMenuContent(
        semanticLabel: '$title column options',
        align: DPopoverAlign.start,
        children: [
          if (onSortChanged != null) ...[
            DDropdownMenuItem(
              leading: const DIcon(DIcons.arrowUp, size: 16),
              onPressed: () =>
                  onSortChanged!(DDataTableSortDirection.ascending),
              child: Text(ascendingLabel),
            ),
            DDropdownMenuItem(
              leading: const _DownArrowIcon(),
              onPressed: () =>
                  onSortChanged!(DDataTableSortDirection.descending),
              child: Text(descendingLabel),
            ),
          ],
          if (onSortChanged != null && onHide != null)
            const DDropdownMenuSeparator(),
          if (onHide != null)
            DDropdownMenuItem(
              leading: const DIcon(DIcons.farEyeSlash, size: 16),
              onPressed: onHide,
              child: Text(hideLabel),
            ),
        ],
      ),
      child: DDropdownMenuTrigger(
        builder: (context, trigger) => Transform.translate(
          offset: Offset(
            Directionality.of(context) == TextDirection.rtl ? 12 : -12,
            0,
          ),
          child: DButton(
            label: Text(title),
            icon: switch (sortDirection) {
              DDataTableSortDirection.ascending => const DIcon(DIcons.arrowUp),
              DDataTableSortDirection.descending => const _DownArrowIcon(),
              null => const _SortIcon(),
            },
            iconPosition: DButtonIconPosition.end,
            variant: DButtonVariant.ghost,
            size: DButtonSize.small,
            hasPopup: true,
            expanded: trigger.open,
            focusNode: trigger.focusNode,
            semanticLabel: switch (sortDirection) {
              DDataTableSortDirection.ascending => '$title, sorted ascending',
              DDataTableSortDirection.descending => '$title, sorted descending',
              null => '$title, not sorted',
            },
            onPressed: trigger.toggle,
          ),
        ),
      ),
    );
  }
}

/// Controlled column visibility menu. Non-hideable columns are omitted.
class DDataTableColumnToggle<T> extends StatelessWidget {
  const DDataTableColumnToggle({
    super.key,
    required this.columns,
    required this.hiddenColumnIds,
    required this.onChanged,
    this.label = 'Columns',
    this.menuLabel = 'Toggle columns',
  });

  final List<DDataTableColumn<T>> columns;
  final Set<String> hiddenColumnIds;
  final ValueChanged<Set<String>>? onChanged;
  final String label;
  final String menuLabel;

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    content: DDropdownMenuContent(
      semanticLabel: menuLabel,
      align: DPopoverAlign.end,
      width: 176,
      children: [
        DDropdownMenuLabel(child: Text(menuLabel)),
        const DDropdownMenuSeparator(),
        for (final column in columns.where((column) => column.hideable))
          DDropdownMenuCheckboxItem(
            checked: !hiddenColumnIds.contains(column.id),
            onChanged: onChanged == null
                ? null
                : (visible) {
                    final hidden = Set<String>.of(hiddenColumnIds);
                    visible ? hidden.remove(column.id) : hidden.add(column.id);
                    onChanged!(Set.unmodifiable(hidden));
                  },
            child: Text(column.label),
          ),
      ],
    ),
    child: DDropdownMenuTrigger(
      builder: (context, trigger) => DButton(
        label: Text(label),
        icon: const DIcon(DIcons.chevronDown),
        iconPosition: DButtonIconPosition.end,
        variant: DButtonVariant.outline,
        size: DButtonSize.regular,
        hasPopup: true,
        expanded: trigger.open,
        focusNode: trigger.focusNode,
        onPressed: onChanged == null ? null : trigger.toggle,
      ),
    ),
  );
}

/// The documented compact text filter composition.
class DDataTableFilterField extends StatelessWidget {
  const DDataTableFilterField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = 'Filter…',
    this.maxWidth = 384,
  });

  final String value;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: DInput(
      value: value,
      hintText: hintText,
      onChanged: onChanged,
      enabled: onChanged != null,
    ),
  );
}

/// Selection summary shared by simple and advanced pagination compositions.
class DDataTableSelectionSummary extends StatelessWidget {
  const DDataTableSelectionSummary({
    super.key,
    required this.selectedCount,
    required this.totalCount,
    this.builder,
  });

  final int selectedCount;
  final int totalCount;
  final String Function(int selected, int total)? builder;

  @override
  Widget build(BuildContext context) => Text(
    builder?.call(selectedCount, totalCount) ??
        '$selectedCount of $totalCount row(s) selected.',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: DTokens.of(context).mutedForeground,
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
    ),
  );
}

/// The reusable Tasks-style Data Table footer: selection summary, page size,
/// current page, and first/previous/next/last outline controls.
///
/// Pass this from [DDataTable.footerBuilder] so [metrics] are derived from the
/// exact filtered model. Page and page-size callbacks may update a shared
/// [DDataTableController] or request an external server query.
class DDataTablePagination extends StatelessWidget {
  DDataTablePagination({
    super.key,
    required this.metrics,
    required this.onPageChanged,
    required this.onPageSizeChanged,
    List<int> pageSizeOptions = const [10, 20, 25, 30, 40, 50],
    this.rowsPerPageLabel = 'Rows per page',
    this.pageLabel,
    this.selectionLabel,
    this.paginationLabel = 'Table pagination',
    this.previousLabel = 'Previous',
    this.nextLabel = 'Next',
    this.enabled = true,
  }) : assert(pageSizeOptions.isNotEmpty),
       assert(pageSizeOptions.isEmpty || pageSizeOptions.first > 0),
       pageSizeOptions = List.unmodifiable(pageSizeOptions);

  final DDataTableMetrics metrics;
  final ValueChanged<int>? onPageChanged;
  final ValueChanged<int>? onPageSizeChanged;
  final List<int> pageSizeOptions;
  final String rowsPerPageLabel;
  final String Function(int page, int pageCount)? pageLabel;
  final String Function(int selected, int total)? selectionLabel;
  final String paginationLabel;
  final String previousLabel;
  final String nextLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    assert(
      pageSizeOptions.toSet().length == pageSizeOptions.length &&
          pageSizeOptions.every((size) => size > 0),
      'Data table page sizes must be positive and unique.',
    );
    final state = metrics.state;
    final choices = pageSizeOptions.contains(state.pageSize)
        ? pageSizeOptions
        : ([...pageSizeOptions, state.pageSize]..sort());
    final textScaler = MediaQuery.textScalerOf(context);
    final valueStyle = DefaultTextStyle.of(context).style.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );
    final widestValue = choices.fold<double>(
      0,
      (width, size) => math.max(
        width,
        TextPainter.computeMaxIntrinsicWidth(
          text: TextSpan(text: '$size', style: valueStyle),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
          locale: Localizations.maybeLocaleOf(context),
        ),
      ),
    );
    // Keep the reference minimum while allowing the Select value, padding,
    // border, gap and chevron to fit with large text or custom page sizes.
    final pageSizeWidth = math.max(70.0, widestValue.ceilToDouble() + 42);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final directionHeight = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => 48.0,
      _ => 32.0,
    };

    Widget rowsPerPage() => Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          rowsPerPageLabel,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: DiscourseTypography.sm,
            height: 20 / 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(
          width: pageSizeWidth,
          child: DSelect<int>.controlled(
            value: state.pageSize,
            onChanged: enabled && onPageSizeChanged != null
                ? (value) {
                    if (value != null) onPageSizeChanged!(value);
                  }
                : null,
            entries: [
              for (final size in choices)
                DSelectOption<int>(
                  value: size,
                  label: '$size',
                  child: Text('$size'),
                ),
            ],
            semanticLabel: rowsPerPageLabel,
            size: DSelectSize.small,
            width: pageSizeWidth,
            side: DPopoverSide.top,
          ),
        ),
      ],
    );

    Widget pageStatus() => SizedBox(
      width: 100,
      child: Text(
        pageLabel?.call(state.page, metrics.pageCount) ??
            'Page ${state.page} of ${metrics.pageCount}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: DiscourseTypography.sm,
          height: 20 / 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    Widget navigation({required bool showFirstLast}) => SizedBox(
      width: showFirstLast ? directionHeight * 4 + 6 : directionHeight * 2 + 2,
      height: directionHeight,
      child: DPaginationNavigation.controlled(
        page: state.page,
        pageCount: metrics.pageCount,
        pageSize: state.pageSize,
        onPageChanged: enabled ? onPageChanged : null,
        showPageNumbers: false,
        showFirstLast: showFirstLast,
        showDirectionText: false,
        directionVariant: DButtonVariant.outline,
        semanticLabel: paginationLabel,
        previousText: previousLabel,
        nextText: nextLabel,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.hasBoundedWidth &&
              constraints.maxWidth >= 720 * scale.clamp(1, 1.5);
          final selection = DDataTableSelectionSummary(
            selectedCount: metrics.selectedFilteredRowCount,
            totalCount: metrics.filteredRowCount,
            builder: selectionLabel,
          );
          if (!wide) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                selection,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    rowsPerPage(),
                    pageStatus(),
                    navigation(showFirstLast: false),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: selection),
              rowsPerPage(),
              const SizedBox(width: 24),
              pageStatus(),
              const SizedBox(width: 16),
              navigation(showFirstLast: true),
            ],
          );
        },
      ),
    );
  }
}

class _DownArrowIcon extends StatelessWidget {
  const _DownArrowIcon();

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.pi,
    child: const DIcon(DIcons.arrowUp, size: 16),
  );
}

class _SortIcon extends StatelessWidget {
  const _SortIcon();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Positioned(top: 0, child: DIcon(DIcons.arrowUp, size: 10)),
        Positioned(
          bottom: 0,
          child: Transform.rotate(
            angle: math.pi,
            child: const DIcon(DIcons.arrowUp, size: 10),
          ),
        ),
      ],
    ),
  );
}
