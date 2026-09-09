import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/data_table_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Data Table registers the documented compositions without promotion',
    () {
      expect(componentExamples['data-table'], same(dataTableExamples));
      expect(dataTableExamples.status, ComponentStatus.baseline);
      expect(dataTableExamples.examples.map((example) => example.title), [
        'Basic table and cell formatting',
        'Sorting, filtering, visibility, selection, and actions',
        'Dynamic data',
        'RTL',
      ]);
    },
  );

  testWidgets('all examples mount at narrow 200 percent RTL in live palettes', (
    tester,
  ) async {
    for (final example in dataTableExamples.examples) {
      for (final theme in StyleguideTheme.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.resolve(AppTheme.light),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: 240,
                      child: Builder(builder: example.builder),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DTable), findsOneWidget, reason: example.title);
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('interactive example changes filter selection and visibility', (
    tester,
  ) async {
    await _show(
      tester,
      'Sorting, filtering, visibility, selection, and actions',
    );
    await tester.enterText(find.byType(DInput), 'Abe');
    await tester.pump();
    expect(find.text('abe45@example.com'), findsOneWidget);
    expect(find.text('ken99@example.com'), findsNothing);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DCheckbox && widget.semanticLabel == 'Select all',
      ),
    );
    await tester.pump();
    expect(find.text('1 of 1 row(s) selected.'), findsOneWidget);

    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DDropdownMenuCheckboxItem).at(2));
    await tester.pump();
    expect(find.text('\$242.00'), findsNothing);
  });

  testWidgets('sortable header applies ascending and descending row order', (
    tester,
  ) async {
    await _show(
      tester,
      'Sorting, filtering, visibility, selection, and actions',
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort ascending'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('abe45@example.com')).dy,
      lessThan(tester.getTopLeft(find.text('carmella@example.com')).dy),
    );

    await tester.tap(find.text('Email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort descending'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('silas22@example.com')).dy,
      lessThan(tester.getTopLeft(find.text('monserrat44@example.com')).dy),
    );
  });

  testWidgets('advanced pagination changes page and page size', (tester) async {
    await _show(
      tester,
      'Sorting, filtering, visibility, selection, and actions',
    );
    expect(find.text('ken99@example.com'), findsOneWidget);
    expect(find.text('lina@example.com'), findsNothing);
    final next = find.byWidgetPredicate(
      (widget) =>
          widget is DButton && widget.semanticLabel == 'Go to next page',
    );
    final vertical = find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(next.first, 300, scrollable: vertical);
    await tester.tap(next.first);
    await tester.pumpAndSettle();
    expect(find.text('ken99@example.com'), findsNothing);
    expect(find.text('lina@example.com'), findsOneWidget);
    expect(find.text('Page 2 of 2'), findsOneWidget);

    final pageSize = find.byWidgetPredicate((widget) => widget is DSelect<int>);
    await tester.scrollUntilVisible(pageSize, 300, scrollable: vertical);
    await tester.tap(pageSize);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20').last);
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 1'), findsOneWidget);
    expect(find.text('ken99@example.com'), findsOneWidget);
    expect(find.text('lina@example.com'), findsOneWidget);
  });

  testWidgets('row action menu targets the stable payment ID', (tester) async {
    await _show(
      tester,
      'Sorting, filtering, visibility, selection, and actions',
    );
    final trigger = find.byWidgetPredicate(
      (widget) =>
          widget is DButton &&
          widget.tooltip == 'Open menu for ken99@example.com',
    );
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('Copy payment ID'), findsOneWidget);
    await tester.tap(find.text('Copy payment ID'));
    await tester.pumpAndSettle();
    expect(find.text('Opened m5gr84i9'), findsOneWidget);
    expect(tester.widget<DButton>(trigger).focusNode?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dynamic example keeps selection with row ID after reorder', (
    tester,
  ) async {
    await _show(tester, 'Dynamic data');
    final selectedBefore = tester
        .widgetList<DCheckbox>(find.byType(DCheckbox))
        .where((checkbox) => checkbox.value == true)
        .length;
    expect(selectedBefore, 1);
    await tester.tap(find.text('Reverse rows'));
    await tester.pump();
    final selectedAfter = tester
        .widgetList<DCheckbox>(find.byType(DCheckbox))
        .where((checkbox) => checkbox.value == true)
        .length;
    expect(selectedAfter, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(WidgetTester tester, String title) async {
  final example = dataTableExamples.examples.firstWhere(
    (example) => example.title == title,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 700, child: Builder(builder: example.builder)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
