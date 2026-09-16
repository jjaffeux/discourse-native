import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(bool dark) {
  final base = dark ? AppTheme.dark : AppTheme.light;
  final tokens = base.extension<DTokens>()!;
  final background = dark ? const Color(0xff303030) : Colors.white;
  return base.copyWith(
    platform: TargetPlatform.macOS,
    scaffoldBackgroundColor: background,
    extensions: [
      ...base.extensions.values,
      tokens.copyWith(background: background, border: background),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  bool dark = true,
  bool lazy = false,
  bool sortable = true,
  TextDirection direction = TextDirection.ltr,
  DDataTableVariant variant = DDataTableVariant.softHeader,
  EdgeInsetsGeometry? padding,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(dark),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              height: lazy ? 220 : null,
              child: DDataTable<String>(
                variant: variant,
                data: const ['Zara', 'Abe'],
                rowId: (row) => row,
                virtualized: lazy,
                columns: [
                  DDataTableColumn(
                    id: 'name',
                    label: 'Name',
                    padding: padding,
                    resizable: true,
                    width: const FixedColumnWidth(250),
                    compare: sortable ? (a, b) => a.compareTo(b) : null,
                    headerBuilder: (_, header) => DDataTableColumnHeader(
                      title: header.column.label,
                      sortDirection: header.sortDirection,
                      onSortChanged: header.onSortChanged,
                    ),
                    cellBuilder: (_, cell) => Text(cell.row),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final lazy in [false, true]) {
    testWidgets(
      'soft headers and separators stay visible across palettes (lazy=$lazy)',
      (tester) async {
        for (final dark in [true, false]) {
          await _pump(tester, dark: dark, lazy: lazy);
          final root = tester.widget<DTable>(find.byType(DTable).first);
          final background = _theme(dark).scaffoldBackgroundColor;
          expect(root.headerBackgroundColor, isNot(background));
          expect(root.borderColor, isNot(background));
          if (!lazy) {
            expect(
              tester.renderObject(find.byType(DTable).first),
              paints..rect(
                rect: const Rect.fromLTWH(0, 0, 500, 41),
                color: root.headerBackgroundColor,
              ),
            );
          }
          final head = find.byType(DTableHead).first;
          final backgrounds = tester.widgetList<AnimatedContainer>(
            find.ancestor(of: head, matching: find.byType(AnimatedContainer)),
          );
          expect(
            backgrounds.any(
              (container) =>
                  (container.decoration as BoxDecoration?)?.color ==
                  root.headerBackgroundColor,
            ),
            isTrue,
          );
          final frame = tester
              .widgetList<DecoratedBox>(
                find.ancestor(
                  of: find.byType(DTable).first,
                  matching: find.byType(DecoratedBox),
                ),
              )
              .where((box) => box.position == DecorationPosition.foreground);
          expect(frame, isNotEmpty);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets('soft header text aligns with its cells in $direction', (
      tester,
    ) async {
      await _pump(tester, direction: direction);
      final header = tester.getRect(find.text('Name'));
      final cell = tester.getRect(find.text('Zara'));
      expect(
        direction == TextDirection.ltr ? header.left : header.right,
        closeTo(direction == TextDirection.ltr ? cell.left : cell.right, .1),
      );
      final bodyCell = find.ancestor(
        of: find.text('Zara'),
        matching: find.byType(DTableCell),
      );
      expect(tester.getSize(bodyCell).height, closeTo(43, .1));
      expect(tester.getSize(find.byType(DTableHead).first).height, 40);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'changing the variant preserves sorting and standard cell geometry',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sort ascending'));
      await tester.pumpAndSettle();
      await _pump(tester, variant: DDataTableVariant.standard);
      expect(
        tester.getTopLeft(find.text('Abe')).dy,
        lessThan(tester.getTopLeft(find.text('Zara')).dy),
      );
      final table = tester.widget<DTable>(find.byType(DTable));
      expect(table.headerBackgroundColor, isNull);
      final cell = find.ancestor(
        of: find.text('Zara'),
        matching: find.byType(DTableCell),
      );
      expect(tester.getSize(cell).height, 36);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit column padding is respected by the soft variant', (
    tester,
  ) async {
    await _pump(tester, padding: EdgeInsets.zero);
    final cell = find.ancestor(
      of: find.text('Zara'),
      matching: find.byType(DTableCell),
    );
    expect(tester.widget<DTableCell>(cell).padding, EdgeInsets.zero);
    expect(tester.getSize(cell).height, 21);
    expect(tester.takeException(), isNull);
  });

  testWidgets('passive reusable headers share the soft typography', (
    tester,
  ) async {
    await _pump(tester, sortable: false);
    final title = tester.widget<Text>(find.text('Name'));
    expect(title.style?.fontSize, 12);
    expect(
      title.style?.color,
      _theme(true).extension<DTokens>()!.mutedForeground,
    );
    expect(tester.takeException(), isNull);
  });
}
