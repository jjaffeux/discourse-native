import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/table_examples.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a multi-column row shares one hover animation clock', (
    tester,
  ) async {
    await _pump(
      tester,
      DTable(
        columnWidths: {
          for (var column = 0; column < 10; column++)
            column: const FixedColumnWidth(50),
        },
        body: DTableBody(
          rows: [
            for (var row = 0; row < 2; row++)
              DTableRow(
                cells: [
                  for (var column = 0; column < 10; column++)
                    DTableCell(child: Text('$row:$column')),
                ],
              ),
          ],
        ),
      ),
    );
    var animationOwners = 0;
    void countOwners(Element element) {
      if (element is StatefulElement && element.state is TickerProvider) {
        animationOwners++;
      }
      element.visitChildren(countOwners);
    }

    countOwners(find.byType(DTable).evaluate().single);
    expect(animationOwners, 2);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('0:0')));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.text('0:9')));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appending rows and changing direction retain a focused cell', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'retained');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    Widget table({
      bool extraRow = false,
      TextDirection direction = TextDirection.ltr,
    }) => Directionality(
      textDirection: direction,
      child: DTable(
        columnWidths: const {
          0: FixedColumnWidth(100),
          1: FixedColumnWidth(100),
        },
        body: DTableBody(
          rows: [
            DTableRow(
              selected: extraRow,
              cells: [
                DTableCell(
                  child: DInput(
                    controller: controller,
                    focusNode: focus,
                    showCursor: false,
                  ),
                ),
                const DTableCell(child: Text('Metadata')),
              ],
            ),
            if (extraRow)
              const DTableRow(
                cells: [
                  DTableCell(child: Text('Added')),
                  DTableCell(child: Text('Second')),
                ],
              ),
          ],
        ),
      ),
    );
    await _pump(tester, table());
    await tester.tap(find.byType(DInput));
    await tester.pumpAndSettle();
    final input = tester.element(find.byType(DInput));
    expect(focus.hasFocus, isTrue);
    await _pump(tester, table(extraRow: true, direction: TextDirection.rtl));
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(DInput)), same(input));
    expect(focus.hasFocus, isTrue);
    expect(controller.text, 'retained');
    expect(
      tester.getTopLeft(find.byType(DInput)).dx,
      greaterThan(tester.getTopLeft(find.text('Metadata')).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a flexible single row shares hover across its cells', (
    tester,
  ) async {
    await _pump(
      tester,
      const DTable(
        columnWidths: {0: FlexColumnWidth(), 1: FixedColumnWidth(120)},
        body: DTableBody(
          rows: [
            DTableRow(
              cells: [
                DTableCell(child: Text('Title')),
                DTableCell(child: Text('Metadata')),
              ],
            ),
          ],
        ),
      ),
    );
    final first = find.text('Title');
    final last = find.text('Metadata');
    expect(tester.getSize(find.byType(DTableCell).first).height, 36);
    expect(tester.getSize(find.byType(DTableCell).last).height, 36);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(first));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(last));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(last).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fitting explicit columns only scroll after narrowing', (
    tester,
  ) async {
    const table = DTable(
      columnWidths: {0: FixedColumnWidth(120), 1: FlexColumnWidth()},
      body: DTableBody(
        rows: [
          DTableRow(
            cells: [
              DTableCell(child: Text('Fixed')),
              DTableCell(softWrap: true, child: Text('Flexible content wraps')),
            ],
          ),
        ],
      ),
    );
    await _pump(tester, table, width: 300);
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.getSize(find.byType(DTableCell).last).width, 180);
    await _pump(tester, table, width: 100);
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 20);
    await tester.drag(find.byType(Scrollable), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    await _pump(tester, table, width: 300);
    await tester.pumpAndSettle();
    expect(find.byType(Scrollable), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicit scroll controllers remain attached to fitting tables', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pump(
      tester,
      DTable(
        controller: controller,
        columnWidths: const {0: FlexColumnWidth()},
        body: const DTableBody(
          rows: [
            DTableRow(cells: [DTableCell(child: Text('Cell'))]),
          ],
        ),
      ),
    );
    expect(controller.hasClients, isTrue);
    expect(controller.position.maxScrollExtent, 0);
  });

  testWidgets('lazy rows share one hover animation across all cells', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        height: 160,
        child: DTable(
          columnWidths: const {
            0: FixedColumnWidth(120),
            1: FixedColumnWidth(120),
            2: FixedColumnWidth(120),
          },
          body: const DTableBody(rows: []),
          rowCount: 2,
          rowBuilder: (context, row) => DTableRow(
            cells: [
              for (var column = 0; column < 3; column++)
                DTableCell(child: Text('Cell $row:$column')),
            ],
          ),
        ),
      ),
    );
    final first = find.text('Cell 0:0');
    final last = find.text('Cell 0:2');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(first));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(last));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(last).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unequal rows keep natural child layout and fill the visible cell',
    (tester) async {
      var layouts = 0;
      var taps = 0;
      var height = 80.0;
      final short = DTableCell(
        key: const ValueKey('short-cell'),
        onTap: () => taps++,
        child: _LayoutProbe(
          onLayout: () => layouts++,
          child: const SizedBox(width: 40, height: 20),
        ),
      );
      Future<void> pumpRow() => _pump(
        tester,
        DTable(
          columnWidths: const {
            0: FixedColumnWidth(200),
            1: FixedColumnWidth(200),
          },
          body: DTableBody(
            rows: [
              DTableRow(
                cells: [
                  short,
                  DTableCell(child: SizedBox(height: height)),
                ],
              ),
            ],
          ),
        ),
      );
      await pumpRow();
      expect(layouts, 1);
      final cell = find.byKey(const ValueKey('short-cell'));
      expect(tester.getSize(cell).height, 96);
      expect(
        tester.getCenter(find.byType(_LayoutProbe)).dy,
        tester.getCenter(cell).dy,
      );
      await tester.tapAt(tester.getBottomLeft(cell) + const Offset(8, -4));
      expect(taps, 1);
      height = 120;
      await pumpRow();
      expect(layouts, 1);
      expect(tester.getSize(cell).height, 136);
      expect(
        tester.getCenter(find.byType(_LayoutProbe)).dy,
        tester.getCenter(cell).dy,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'equal-height cells lay out once and hover does not relayout them',
    (tester) async {
      var layouts = 0;
      await _pump(
        tester,
        DTable(
          columnWidths: const {
            0: FixedColumnWidth(200),
            1: FixedColumnWidth(200),
          },
          body: DTableBody(
            rows: [
              DTableRow(
                cells: [
                  _MeasuredCell(onLayout: () => layouts++),
                  _MeasuredCell(onLayout: () => layouts++),
                ],
              ),
            ],
          ),
        ),
      );
      expect(layouts, 2);
      layouts = 0;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byType(_LayoutProbe).first));
      await tester.pumpAndSettle();
      expect(layouts, 0);
      await mouse.moveTo(tester.getCenter(find.byType(_LayoutProbe).last));
      await tester.pumpAndSettle();
      expect(layouts, 0);
    },
  );

  testWidgets(
    'lazy footer and caption retain natural height and footer style',
    (tester) async {
      final scroll = ScrollController();
      await _pump(
        tester,
        SizedBox(
          height: 320,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: DTable(
              columnWidths: const {0: FixedColumnWidth(280)},
              header: const DTableHeader(
                rows: [
                  DTableRow(cells: [DTableHead(child: Text('Name'))]),
                ],
              ),
              body: const DTableBody(rows: []),
              rowCount: 100,
              verticalScrollController: scroll,
              rowBuilder: (context, index) =>
                  DTableRow(cells: [DTableCell(child: Text('Member $index'))]),
              footer: const DTableFooter(
                rows: [
                  DTableRow(cells: [DTableCell(child: Text('Total 100'))]),
                ],
              ),
              caption: const DTableCaption(child: Text('Directory caption')),
            ),
          ),
        ),
      );
      final footer = find.text('Total 100');
      final caption = find.text('Directory caption');
      expect(footer, findsOneWidget);
      expect(caption, findsOneWidget);
      expect(
        DefaultTextStyle.of(tester.element(footer)).style.fontWeight,
        FontWeight.w500,
      );
      expect(tester.getSize(footer).height, greaterThan(20));
      final top = tester.getTopLeft(footer);
      expect(
        tester.getTopLeft(caption).dy,
        greaterThan(tester.getBottomLeft(footer).dy),
      );
      scroll.jumpTo(1000);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(footer), top);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  testWidgets('invoice columns align with spanning footer and caption gap', (
    tester,
  ) async {
    await _pump(tester, const TableInvoiceExample(count: 3));
    final first = find.byType(DTableHead).first;
    expect(tester.getSize(first).width, greaterThanOrEqualTo(100));
    expect(tester.getSize(first).height, 40);
    expect(
      tester.getTopLeft(find.text('INV001')).dx,
      tester.getTopLeft(find.text('Invoice')).dx,
    );
    expect(
      tester.getBottomRight(find.text('\$2,500.00')).dx,
      tester.getBottomRight(find.text('\$250.00')).dx,
    );
    expect(tester.getSize(find.byType(DTableCell).first).height, 36);
    final caption = find.text('A list of your recent invoices.');
    final footer = find.byWidgetPredicate(
      (w) => w is DTableCell && w.columnSpan == 3,
    );
    expect(tester.getTopLeft(caption).dy - tester.getBottomLeft(footer).dy, 16);
    final style = DefaultTextStyle.of(
      tester.element(find.text('Invoice')),
    ).style;
    expect(style.fontSize, 14);
    expect(style.height, 20 / 14);
    expect(style.fontWeight, FontWeight.w500);
  });

  testWidgets(
    'semantic table contains ordered rows, headers and row selection',
    (tester) async {
      final handle = tester.ensureSemantics();

      await _pump(
        tester,
        const DTable(
          header: DTableHeader(
            rows: [
              DTableRow(
                cells: [
                  DTableHead(child: Text('Name')),
                  DTableHead(child: Text('Amount')),
                ],
              ),
            ],
          ),
          body: DTableBody(
            rows: [
              DTableRow(
                selected: true,
                cells: [
                  DTableCell(child: Text('Alice')),
                  DTableCell(child: Text('10')),
                ],
              ),
            ],
          ),
        ),
      );
      final nodes = _nodes(
        tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
      );
      final table = nodes.singleWhere((n) => n.role == SemanticsRole.table);
      final rows = <SemanticsNode>[];
      table.visitChildren((n) {
        rows.add(n);
        return true;
      });
      expect(rows.map((n) => n.role), [SemanticsRole.row, SemanticsRole.row]);
      expect(
        _nodes(
          rows[0],
        ).where((n) => n.role == SemanticsRole.columnHeader).length,
        2,
      );
      expect(rows[0].flagsCollection.isSelected, Tristate.none);
      expect(rows[1].flagsCollection.isSelected, Tristate.isTrue);
      expect(
        _nodes(
          rows[1],
        ).skip(1).where((n) => n.flagsCollection.isSelected == Tristate.isTrue),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      handle.dispose();
    },
  );

  testWidgets(
    'narrow RTL large text scrolls naturally and preserves borrowed controller',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: DTable(
              controller: controller,
              header: const DTableHeader(
                rows: [
                  DTableRow(
                    cells: [
                      DTableHead(child: Text('First column')),
                      DTableHead(child: Text('Last column')),
                    ],
                  ),
                ],
              ),
              body: const DTableBody(
                rows: [
                  DTableRow(
                    cells: [
                      DTableCell(child: Text('Long readable content')),
                      DTableCell(child: Text('Amount')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        width: 240,
      );
      expect(controller.position.maxScrollExtent, greaterThan(0));
      expect(
        tester.getTopLeft(find.text('First column')).dx,
        greaterThan(tester.getTopLeft(find.text('Last column')).dx),
      );
      expect(tester.getSize(find.byType(DTableCell).first).height, 56);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _pump(tester, const SizedBox());
      expect(controller.hasClients, isFalse);
      controller.addListener(() {});
    },
  );

  testWidgets('composed menu preserves edit, duplicate, and delete actions', (
    tester,
  ) async {
    await _pump(tester, const TableActionsExample());
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Wireless Mouse (edited)'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);

    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(find.text('Wireless Mouse (edited) (copy)'), findsOneWidget);
    expect(find.text('Duplicate: Wireless Mouse (edited)'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Wireless Mouse (edited)'), findsNothing);
    expect(find.text('Delete: Wireless Mouse (edited)'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every table example fits a narrow large-text scroll viewport', (
    tester,
  ) async {
    for (final example in tableExamples.examples) {
      await _pump(
        tester,
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SingleChildScrollView(
            child: Builder(builder: example.builder),
          ),
        ),
        width: 360,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: example.title);
    }
  });

  testWidgets(
    'fixed and flexible columns permit wrapped layout-builder content',
    (tester) async {
      await _pump(
        tester,
        DTable(
          columnWidths: const {0: FixedColumnWidth(100), 1: FlexColumnWidth()},
          body: DTableBody(
            rows: [
              DTableRow(
                cells: [
                  const DTableCell(
                    softWrap: true,
                    child: Text('A long wrapped description'),
                  ),
                  DTableCell(
                    child: LayoutBuilder(
                      builder: (_, constraints) =>
                          Text('Width ${constraints.maxWidth}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        width: 300,
      );
      expect(tester.getSize(find.byType(DTableCell).first).width, 100);
      expect(tester.getSize(find.byType(DTableCell).last).width, 200);
      expect(tester.takeException(), isNull);
    },
  );
}

List<SemanticsNode> _nodes(SemanticsNode node) => [
  node,
  ...[
    for (final child in (() {
      final result = <SemanticsNode>[];
      node.visitChildren((n) {
        result.add(n);
        return true;
      });
      return result;
    })())
      ..._nodes(child),
  ],
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 600,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

class _MeasuredCell extends DTableCell {
  const _MeasuredCell({required this.onLayout})
    : super(child: const SizedBox());
  final VoidCallback onLayout;
  @override
  Widget build(BuildContext context) =>
      _LayoutProbe(onLayout: onLayout, child: const SizedBox(height: 32));
}

class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe({required this.onLayout, required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LayoutCounter(onLayout);
}

class _LayoutCounter extends RenderProxyBox {
  _LayoutCounter(this.onLayout);
  final VoidCallback onLayout;
  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}
