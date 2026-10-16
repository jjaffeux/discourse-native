import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/component_examples.dart';
import 'package:discourse_native/src/styleguide/examples/data_table_examples.dart';
import 'package:discourse_native/src/styleguide/styleguide_example.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Data Table registers the accepted documented compositions', () {
    expect(componentExamples['data-table'], same(dataTableExamples));
    expect(dataTableExamples.status, ComponentStatus.implemented);
    expect(dataTableExamples.examples.map((example) => example.title), [
      'Borderless page table',
      'Soft header',
      'Resizable virtual directory',
      'Basic table and cell formatting',
      'Sorting and row actions',
      'Dynamic data',
      'RTL',
      'Editable cell surface',
    ]);
  });

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
        expect(
          find.byWidgetPredicate((widget) => widget is DDataTable),
          findsOneWidget,
          reason: example.title,
        );
        expect(find.byType(DTable), findsWidgets, reason: example.title);
        expect(tester.takeException(), isNull, reason: example.title);
      }
    }
  });

  testWidgets('sortable header applies ascending and descending row order', (
    tester,
  ) async {
    await _show(tester, 'Sorting and row actions');

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

  testWidgets('row action menu targets the stable payment ID', (tester) async {
    await _show(tester, 'Sorting and row actions');
    expect(find.text('Actions'), findsNothing);
    final trigger = find.byWidgetPredicate(
      (widget) =>
          widget is DButton &&
          widget.tooltip == 'Open menu for ken99@example.com',
    );
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Copy payment ID'), findsOneWidget);
    await tester.tap(find.text('Copy payment ID'));
    await tester.pumpAndSettle();
    expect(find.text('Opened m5gr84i9'), findsOneWidget);
    expect(tester.widget<DButton>(trigger).focusNode?.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dynamic example reorders stable rows', (tester) async {
    await _show(tester, 'Dynamic data');
    expect(
      tester.getTopLeft(find.text('ken99@example.com')).dy,
      lessThan(tester.getTopLeft(find.text('abe45@example.com')).dy),
    );
    await tester.tap(find.text('Reverse rows'));
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('ken99@example.com')).dy,
      greaterThan(tester.getTopLeft(find.text('abe45@example.com')).dy),
    );
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
