import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/examples/table_examples.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  testWidgets(
    'hover expanded and selected use live multiplied alpha with reduced motion',
    (tester) async {
      final colors = ThemeData().colorScheme;
      final tokens = DTokens.fromTheme(
        ThemeData(),
      ).copyWith(muted: const Color(0x80334455));
      Widget table({bool selected = false, bool expanded = false}) => DTable(
        body: DTableBody(
          rows: [
            DTableRow(
              selected: selected,
              expanded: expanded,
              cells: const [DTableCell(child: Text('Row'))],
            ),
          ],
        ),
      );
      Future<void> pump(Widget child, DTokens t) => _pump(
        tester,
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: child,
        ),
        theme: ThemeData(colorScheme: colors, extensions: [t]),
      );
      Color? background() =>
          (tester
                      .widget<AnimatedContainer>(
                        find
                            .descendant(
                              of: find.byType(DTable),
                              matching: find.byType(AnimatedContainer),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      await pump(table(), tokens);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Row')));
      await tester.pump();
      expect(background(), tokens.muted.withValues(alpha: tokens.muted.a * .5));
      await mouse.moveTo(Offset.zero);
      await pump(table(expanded: true), tokens);
      expect(background(), tokens.muted.withValues(alpha: tokens.muted.a * .5));
      final changed = tokens.copyWith(muted: const Color(0x40665544));
      await pump(table(selected: true), changed);
      await tester.pumpAndSettle();
      expect(background(), changed.muted);
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
            .duration,
        Duration.zero,
      );
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
