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
        body: SizedBox(width: 700, child: Builder(builder: example.builder)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
