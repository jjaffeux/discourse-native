import 'dart:convert';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resizing and paging retain the sorted row order', (
    tester,
  ) async {
    var comparisons = 0;
    var resizeChanges = 0;
    final rows = List.generate(1000, (index) => 1000 - index);
    final columns = [
      DDataTableColumn<int>(
        id: 'value',
        label: 'Value',
        resizable: true,
        width: const FixedColumnWidth(240),
        compare: (first, second) {
          comparisons++;
          return first.compareTo(second);
        },
        cellBuilder: (_, cell) => Text('Row ${cell.row}'),
      ),
    ];
    var state = DDataTableState(
      sort: const DDataTableSort(
        columnId: 'value',
        direction: DDataTableSortDirection.ascending,
      ),
      pageSize: 25,
    );
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return DDataTable<int>(
            data: rows,
            columns: columns,
            rowId: (row) => row,
            state: state,
            onStateChanged: (next) => setState(() => state = next),
            onColumnWidthsChanged: (_) => resizeChanges++,
          );
        },
      ),
    );
    final initialComparisons = comparisons;
    expect(initialComparisons, greaterThan(0));
    expect(_visibleRows(tester), List.generate(25, (index) => index + 1));
    final initialWidth = tester
        .widget<DResizableHandle>(find.byType(DResizableHandle))
        .value;
    final resizeComparisons = <int>[];
    for (var index = 0; index < 5; index++) {
      final before = comparisons;
      await tester.drag(find.byType(DResizableHandle), const Offset(60, 0));
      await tester.pumpAndSettle();
      resizeComparisons.add(comparisons - before);
    }
    expect(resizeChanges, greaterThanOrEqualTo(5));
    expect(
      tester.widget<DResizableHandle>(find.byType(DResizableHandle)).value,
      greaterThan(initialWidth),
    );
    final beforePage = comparisons;
    update(() => state = state.copyWith(page: 2));
    await tester.pumpAndSettle();
    final pageComparisons = comparisons - beforePage;
    expect(_visibleRows(tester), List.generate(25, (index) => index + 26));
    final beforePageSize = comparisons;
    update(() => state = state.copyWith(pageSize: 10));
    await tester.pumpAndSettle();
    final pageSizeComparisons = comparisons - beforePageSize;
    expect(_visibleRows(tester), List.generate(10, (index) => index + 11));
    debugPrint(
      jsonEncode({
        'probe': 'dataTableRowCache',
        'sourceRows': rows.length,
        'pageRows': 25,
        'initialComparisons': initialComparisons,
        'resizeComparisons': resizeComparisons,
        'pageComparisons': pageComparisons,
        'pageSizeComparisons': pageSizeComparisons,
        'resizeUpdates': resizeChanges,
      }),
    );
    expect(resizeComparisons, everyElement(0));
    expect(pageComparisons, 0);
    expect(pageSizeComparisons, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row cache follows data, sort, filters and column behavior', (
    tester,
  ) async {
    var comparisons = 0;
    var filterCalls = 0;
    var rows = [5, 1, 3, 2, 4];
    var state = DDataTableState(
      sort: const DDataTableSort(
        columnId: 'value',
        direction: DDataTableSortDirection.ascending,
      ),
      filters: const {'value': '3'},
      selectedRowIds: const {3, 99},
      pageSize: 2,
    );
    final selected = <int, bool>{};
    DDataTableColumn<int> column({bool reverse = false, bool below = false}) =>
        _FilterColumn(
          compare: (first, second) {
            comparisons++;
            return reverse ? second.compareTo(first) : first.compareTo(second);
          },
          matchesRow: (row, query) {
            filterCalls++;
            return below ? row <= int.parse(query) : row >= int.parse(query);
          },
          cellBuilder: (_, cell) {
            selected[cell.row] = cell.selected;
            return Text('Row ${cell.row}');
          },
        );
    var columns = [column()];
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return DDataTable<int>(
            data: rows,
            columns: columns,
            rowId: (row) => row,
            state: state,
            onStateChanged: (next) => setState(() => state = next),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [3, 4]);
    expect(selected[3], isTrue);
    expect(state.selectedRowIds, {3});
    var before = comparisons;
    var filtersBefore = filterCalls;
    update(() => state = state.copyWith(selectedRowIds: {4}));
    await tester.pumpAndSettle();
    expect(selected[3], isFalse);
    expect(selected[4], isTrue);
    expect(comparisons, before);
    expect(filterCalls, filtersBefore);

    update(() => state = state.copyWith(page: 2));
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [5]);
    expect(comparisons, before);
    expect(filterCalls, filtersBefore);

    update(() => rows = [8, 6, 4, 2]);
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [8]);
    expect(comparisons, greaterThan(before));
    expect(filterCalls, greaterThan(filtersBefore));

    before = comparisons;
    update(() => state = state.copyWith(filters: {'value': '6'}));
    await tester.pumpAndSettle();
    expect(state.page, 1);
    expect(_visibleRows(tester), [6, 8]);
    expect(comparisons, greaterThan(before));

    before = comparisons;
    update(() {
      state = state.copyWith(
        sort: const DDataTableSort(
          columnId: 'value',
          direction: DDataTableSortDirection.descending,
        ),
      );
    });
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [8, 6]);
    expect(comparisons, greaterThan(before));

    before = comparisons;
    update(() => columns = [column(reverse: true)]);
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [6, 8]);
    expect(comparisons, greaterThan(before));

    update(() => columns = [column(below: true)]);
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [6, 4]);

    update(
      () => columns = [
        DDataTableColumn<int>(
          id: 'value',
          label: 'Value',
          cellBuilder: (_, cell) => Text('Row ${cell.row}'),
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(state.sort, isNull);
    expect(state.filters, isEmpty);
    expect(_visibleRows(tester), [8, 6]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached sorting keeps source order for ties in both directions', (
    tester,
  ) async {
    var rows = <({int id, int rank})>[
      (id: 1, rank: 2),
      (id: 2, rank: 1),
      (id: 3, rank: 2),
      (id: 4, rank: 1),
    ];
    var state = DDataTableState(
      sort: const DDataTableSort(
        columnId: 'value',
        direction: DDataTableSortDirection.ascending,
      ),
    );
    final columns = [
      DDataTableColumn<({int id, int rank})>(
        id: 'value',
        label: 'Value',
        compare: (first, second) => first.rank.compareTo(second.rank),
        cellBuilder: (_, cell) => Text('Row ${cell.row.id}'),
      ),
    ];
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return DDataTable<({int id, int rank})>(
            data: rows,
            columns: columns,
            rowId: (row) => row.id,
            state: state,
            onStateChanged: (next) => setState(() => state = next),
          );
        },
      ),
    );
    expect(_visibleRows(tester), [2, 4, 1, 3]);
    update(
      () => state = state.copyWith(
        sort: const DDataTableSort(
          columnId: 'value',
          direction: DDataTableSortDirection.descending,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [1, 3, 2, 4]);
    update(() => rows = rows.reversed.toList());
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [3, 1, 4, 2]);
    update(() => state = state.copyWith(sort: null));
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [4, 3, 2, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual mode bypasses local cache across mode and data changes', (
    tester,
  ) async {
    var comparisons = 0;
    var filterCalls = 0;
    var rows = [5, 1, 3];
    var mode = DDataTableOperationMode.local;
    var state = DDataTableState(
      sort: const DDataTableSort(
        columnId: 'value',
        direction: DDataTableSortDirection.ascending,
      ),
      filters: const {'value': '3'},
      pageSize: 1,
    );
    final columns = [
      _FilterColumn(
        compare: (first, second) {
          comparisons++;
          return first.compareTo(second);
        },
        matchesRow: (row, query) {
          filterCalls++;
          return row >= int.parse(query);
        },
        cellBuilder: (_, cell) => Text('Row ${cell.row}'),
      ),
    ];
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          update = setState;
          return DDataTable<int>(
            data: rows,
            columns: columns,
            rowId: (row) => row,
            state: state,
            onStateChanged: (next) => setState(() => state = next),
            operationMode: mode,
            rowCount: mode == DDataTableOperationMode.manual ? 100 : null,
          );
        },
      ),
    );
    expect(_visibleRows(tester), [3]);
    final before = comparisons;
    final filtersBefore = filterCalls;
    update(() => mode = DDataTableOperationMode.manual);
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [5, 1, 3]);
    update(() {
      rows = [8, 2, 6];
      state = state.copyWith(page: 20, selectedRowIds: {99});
    });
    await tester.pumpAndSettle();
    expect(_visibleRows(tester), [8, 2, 6]);
    expect(state.page, 20);
    expect(state.selectedRowIds, {99});
    expect(comparisons, before);
    expect(filterCalls, filtersBefore);
    update(() => mode = DDataTableOperationMode.local);
    await tester.pumpAndSettle();
    expect(state.page, 2);
    expect(state.selectedRowIds, isEmpty);
    expect(_visibleRows(tester), [8]);
    expect(comparisons, greaterThan(before));
    expect(filterCalls, greaterThan(filtersBefore));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

List<int> _visibleRows(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(DTableCell), matching: find.byType(Text)),
    )
    .map((text) => int.parse(text.data!.substring(4)))
    .toList();

class _FilterColumn extends DDataTableColumn<int> {
  const _FilterColumn({
    required super.compare,
    required super.cellBuilder,
    required this.matchesRow,
  }) : super(id: 'value', label: 'Value');

  final DDataTableFilter<int> matchesRow;

  @override
  bool get filterable => true;

  @override
  bool matches(int row, String query) => matchesRow(row, query);
}
