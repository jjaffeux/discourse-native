import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Payment = ({String id, String email, int amount});

const _payments = <_Payment>[
  (id: 'a', email: 'zara@example.com', amount: 30),
  (id: 'b', email: 'abe@example.com', amount: 10),
  (id: 'c', email: 'mina@example.com', amount: 20),
];

List<DDataTableColumn<_Payment>> _columns() => [
  DDataTableColumn(
    id: 'email',
    label: 'Email',
    compare: (first, second) => first.email.compareTo(second.email),
    filterText: (row) => row.email,
    headerBuilder: (context, header) => DDataTableColumnHeader(
      title: header.column.label,
      sortDirection: header.sortDirection,
      onSortChanged: header.onSortChanged,
      onHide: header.onVisibilityChanged == null
          ? null
          : () => header.onVisibilityChanged!(false),
    ),
    cellBuilder: (context, cell) => Text(cell.row.email),
  ),
  DDataTableColumn(
    id: 'amount',
    label: 'Amount',
    compare: (first, second) => first.amount.compareTo(second.amount),
    filterText: (row) => '${row.amount}',
    alignment: AlignmentDirectional.centerEnd,
    headerAlignment: AlignmentDirectional.centerEnd,
    cellBuilder: (context, cell) => Text('\$${cell.row.amount}.00'),
  ),
];

void main() {
  test('controller updates reset page and retain independent state', () {
    final controller = DDataTableController(
      initialState: DDataTableState(
        page: 3,
        selectedRowIds: const {'a'},
        hiddenColumnIds: const {'amount'},
      ),
    );
    addTearDown(controller.dispose);

    controller.setFilter('email', 'abe');
    expect(controller.value.page, 1);
    expect(controller.value.filters, {'email': 'abe'});
    expect(controller.value.selectedRowIds, {'a'});
    expect(controller.value.hiddenColumnIds, {'amount'});

    controller.setSort('email', DDataTableSortDirection.descending);
    expect(controller.value.sort?.columnId, 'email');
    expect(
      controller.value.sort?.direction,
      DDataTableSortDirection.descending,
    );
    controller.setPageRowsSelected(['b', 'c'], true);
    expect(controller.value.selectedRowIds, {'a', 'b', 'c'});
    controller.setPageSize(20);
    expect(controller.value.pageSize, 20);
    expect(controller.value.page, 1);
  });

  testWidgets('local filter sort page and stable selection compose', (
    tester,
  ) async {
    final controller = DDataTableController(
      initialState: DDataTableState(pageSize: 2),
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      DDataTable<_Payment>(
        data: _payments,
        columns: _columns(),
        rowId: (row) => row.id,
        controller: controller,
        selectable: true,
        selectRowLabel: (row) => 'Select ${row.email}',
      ),
    );

    expect(find.text('zara@example.com'), findsOneWidget);
    expect(find.text('abe@example.com'), findsOneWidget);
    expect(find.text('mina@example.com'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Select abe@example.com'));
    await tester.pump();
    expect(controller.value.selectedRowIds, {'b'});

    controller.setSort('email', DDataTableSortDirection.ascending);
    await tester.pump();
    expect(find.text('abe@example.com'), findsOneWidget);
    expect(find.text('mina@example.com'), findsOneWidget);
    expect(find.text('zara@example.com'), findsNothing);
    expect(controller.value.selectedRowIds, {'b'});

    controller.setFilter('email', 'zara');
    await tester.pump();
    expect(find.text('zara@example.com'), findsOneWidget);
    expect(find.text('abe@example.com'), findsNothing);
    expect(controller.value.selectedRowIds, {'b'});

    controller.setFilter('email', 'missing');
    await tester.pump();
    expect(find.text('No results.'), findsOneWidget);
    expect(tester.getSize(find.text('No results.')).height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection is keyed by IDs across row replacement and pruned', (
    tester,
  ) async {
    final controller = DDataTableController(
      initialState: DDataTableState(selectedRowIds: const {'b'}),
    );
    addTearDown(controller.dispose);
    var rows = List<_Payment>.of(_payments);
    late StateSetter rebuild;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return DDataTable<_Payment>(
            data: rows,
            columns: _columns(),
            rowId: (row) => row.id,
            controller: controller,
            selectable: true,
          );
        },
      ),
    );
    var selected = tester.widget<DCheckbox>(find.byType(DCheckbox).at(2));
    expect(selected.value, isTrue);

    rebuild(() => rows = [rows[1], rows[0]]);
    await tester.pump();
    selected = tester.widget<DCheckbox>(find.byType(DCheckbox).at(1));
    expect(selected.value, isTrue);

    rebuild(() => rows = [rows[1]]);
    await tester.pump();
    await tester.pump();
    expect(controller.value.selectedRowIds, isEmpty);
    expect(
      tester.widget<DCheckbox>(find.byType(DCheckbox).first).value,
      isFalse,
    );
  });

  testWidgets('manual mode reports state without reprocessing server page', (
    tester,
  ) async {
    var state = DDataTableState(
      sort: const DDataTableSort(
        columnId: 'email',
        direction: DDataTableSortDirection.ascending,
      ),
      filters: const {'email': 'does-not-match'},
      page: 3,
      pageSize: 1,
    );
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => DDataTable<_Payment>(
          data: [_payments.first],
          columns: _columns(),
          rowId: (row) => row.id,
          operationMode: DDataTableOperationMode.manual,
          rowCount: 5,
          pageCount: 5,
          state: state,
          onStateChanged: (next) => setState(() => state = next),
        ),
      ),
    );
    expect(find.text('zara@example.com'), findsOneWidget);

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort descending'));
    await tester.pumpAndSettle();
    expect(state.page, 1);
    expect(state.sort?.direction, DDataTableSortDirection.descending);
    expect(find.text('zara@example.com'), findsOneWidget);
  });

  testWidgets('column menu toggles repeatedly and all-hidden stays valid', (
    tester,
  ) async {
    var hidden = <String>{};
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            DDataTableColumnToggle<_Payment>(
              columns: _columns(),
              hiddenColumnIds: hidden,
              onChanged: (next) => setState(() => hidden = next),
            ),
            DDataTable<_Payment>(
              data: _payments,
              columns: _columns(),
              rowId: (row) => row.id,
              state: DDataTableState(hiddenColumnIds: hidden),
              onStateChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DDropdownMenuCheckboxItem).first);
    await tester.pump();
    expect(hidden, {'email'});
    expect(find.text('zara@example.com'), findsNothing);
    await tester.tap(find.byType(DDropdownMenuCheckboxItem).last);
    await tester.pump();
    expect(hidden, {'email', 'amount'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow 200 percent RTL scrolls and keyboard opens header menu', (
    tester,
  ) async {
    await _pump(
      tester,
      Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: DDataTable<_Payment>(
            data: _payments,
            columns: _columns(),
            rowId: (row) => row.id,
            minimumWidth: 520,
          ),
        ),
      ),
      width: 240,
    );
    expect(
      tester.getTopRight(find.text('zara@example.com')).dx,
      greaterThan(tester.getTopRight(find.text('\$30.00')).dx),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Sort ascending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, Widget child, {double width = 700}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
