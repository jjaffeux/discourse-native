import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    expect(
      tester.widget<DCheckbox>(find.byType(DCheckbox).first).value,
      isNull,
    );

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

  testWidgets('page selection exposes none, all, mixed, then none', (
    tester,
  ) async {
    final controller = DDataTableController();
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

    DCheckbox header() =>
        tester.widget<DCheckbox>(find.byType(DCheckbox).first);
    expect(header().value, isFalse);

    await tester.tap(find.bySemanticsLabel('Select all rows on this page'));
    await tester.pump();
    expect(controller.value.selectedRowIds, {'a', 'b', 'c'});
    expect(header().value, isTrue);

    await tester.tap(find.bySemanticsLabel('Select abe@example.com'));
    await tester.pump();
    expect(controller.value.selectedRowIds, {'a', 'c'});
    expect(header().value, isNull);

    await tester.tap(find.bySemanticsLabel('Select zara@example.com'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Select mina@example.com'));
    await tester.pump();
    expect(controller.value.selectedRowIds, isEmpty);
    expect(header().value, isFalse);
  });

  testWidgets('selection header exposes column and select-all semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = DDataTableController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      DDataTable<_Payment>(
        data: _payments,
        columns: _columns(),
        rowId: (row) => row.id,
        controller: controller,
        selectable: true,
        selectionColumnLabel: 'Payment selection',
        selectAllLabel: 'Select every payment on this page',
      ),
    );

    expect(find.bySemanticsLabel('Payment selection'), findsOneWidget);
    final selectAll = find.bySemanticsLabel(
      'Select every payment on this page',
    );
    expect(selectAll, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.value.selectedRowIds, {'a', 'b', 'c'});
    semantics.dispose();
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

  testWidgets('footer receives exact local and manual pagination metrics', (
    tester,
  ) async {
    final controller = DDataTableController(
      initialState: DDataTableState(
        selectedRowIds: const {'a', 'c'},
        pageSize: 2,
      ),
    );
    addTearDown(controller.dispose);
    DDataTableMetrics? metrics;
    await _pump(
      tester,
      DDataTable<_Payment>(
        data: _payments,
        columns: _columns(),
        rowId: (row) => row.id,
        controller: controller,
        footerBuilder: (context, value) {
          metrics = value;
          return Text('Page ${value.state.page} of ${value.pageCount}');
        },
      ),
    );
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(metrics?.filteredRowCount, 3);
    expect(metrics?.selectedFilteredRowCount, 2);

    await _pump(
      tester,
      DDataTable<_Payment>(
        data: [_payments.last],
        columns: _columns(),
        rowId: (row) => row.id,
        operationMode: DDataTableOperationMode.manual,
        rowCount: 21,
        pageCount: 3,
        selectedFilteredRowCount: 7,
        state: DDataTableState(page: 2, pageSize: 10),
        onStateChanged: (_) {},
        footerBuilder: (context, value) {
          metrics = value;
          return Text('Page ${value.state.page} of ${value.pageCount}');
        },
      ),
    );
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(metrics?.filteredRowCount, 21);
    expect(metrics?.selectedFilteredRowCount, 7);
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

  testWidgets('advanced footer reuses outline Pagination and Select owners', (
    tester,
  ) async {
    var page = 2;
    var pageSize = 10;
    Widget footer({required bool narrow}) => MediaQuery(
      data: MediaQueryData(
        size: Size(narrow ? 240 : 1000, 700),
        textScaler: TextScaler.linear(narrow ? 2 : 1),
      ),
      child: DDataTablePagination(
        metrics: DDataTableMetrics(
          state: DDataTableState(page: page, pageSize: pageSize),
          pageCount: 3,
          filteredRowCount: 21,
          selectedFilteredRowCount: 2,
        ),
        onPageChanged: (value) => page = value,
        onPageSizeChanged: (value) => pageSize = value,
      ),
    );

    await _pump(tester, footer(narrow: false), width: 1000);
    final directionButtons = tester
        .widgetList<DButton>(find.byType(DButton))
        .where((button) => button.semanticLabel?.startsWith('Go to ') == true)
        .toList();
    expect(directionButtons, hasLength(4));
    expect(
      directionButtons.every(
        (button) => button.variant == DButtonVariant.outline,
      ),
      isTrue,
    );
    expect(find.byType(DSelect<int>), findsOneWidget);
    expect(find.text('2 of 21 row(s) selected.'), findsOneWidget);

    await _pump(tester, footer(narrow: true), width: 240);
    final narrowButtons = tester
        .widgetList<DButton>(find.byType(DButton))
        .where((button) => button.semanticLabel?.startsWith('Go to ') == true)
        .toList();
    expect(narrowButtons, hasLength(2));
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

  for (final direction in TextDirection.values) {
    testWidgets('page size stays readable at 200 percent in $direction', (
      tester,
    ) async {
      var pageSize = 10;
      await _pump(
        tester,
        Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: StatefulBuilder(
              builder: (context, setState) => DDataTablePagination(
                metrics: DDataTableMetrics(
                  state: DDataTableState(pageSize: pageSize),
                  pageCount: 1,
                  filteredRowCount: 10,
                  selectedFilteredRowCount: 0,
                ),
                pageSizeOptions: const [10, 1000],
                onPageChanged: (_) {},
                onPageSizeChanged: (value) => setState(() => pageSize = value),
              ),
            ),
          ),
        ),
        width: 240,
      );

      void expectReadableValue(String value) {
        final label = find.descendant(
          of: find.byType(DSelect<int>),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RichText && widget.text.toPlainText() == value,
          ),
        );
        expect(label, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
        );
      }

      expectReadableValue('10');
      await tester.tap(find.byType(DSelect<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1000'));
      await tester.pumpAndSettle();
      expect(pageSize, 1000);
      expectReadableValue('1000');
      expect(tester.takeException(), isNull);
    });
  }
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
