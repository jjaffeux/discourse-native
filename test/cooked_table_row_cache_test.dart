import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

void main() {
  testWidgets('cooked table retains row inputs when sorting and paging', (
    tester,
  ) async {
    Future<void> pumpTable() async {
      final element = html
          .parseFragment(
            '<table><tr><th>Value</th></tr>'
            '${List.generate(60, (index) => '<tr><td>${60 - index}</td></tr>').join()}'
            '</table>',
          )
          .querySelector('table')!;
      final table = cookedTableWidgetBuilder(
        element,
        cellBuilder: (_, content) => Text(html.parse(content).body!.text),
      )!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: table)),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpTable();
    final original = tester.widget<DDataTable<int>>(
      find.byType(DDataTable<int>),
    );
    await tester.tap(find.text('Value'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort ascending'));
    await tester.pumpAndSettle();
    var current = tester.widget<DDataTable<int>>(find.byType(DDataTable<int>));
    expect(current.data, same(original.data));
    expect(current.columns, same(original.columns));
    expect(_visibleValues(tester), List.generate(25, (index) => index + 1));

    await tester.ensureVisible(find.byType(DPaginationNext));
    await tester.tap(find.byType(DPaginationNext));
    await tester.pumpAndSettle();
    current = tester.widget<DDataTable<int>>(find.byType(DDataTable<int>));
    expect(current.data, same(original.data));
    expect(current.columns, same(original.columns));
    expect(_visibleValues(tester), List.generate(25, (index) => index + 26));

    await pumpTable();
    current = tester.widget<DDataTable<int>>(find.byType(DDataTable<int>));
    expect(current.data, same(original.data));
    expect(current.columns, same(original.columns));
    expect(current.state!.page, 2);
    expect(_visibleValues(tester), List.generate(25, (index) => index + 26));

    await tester.ensureVisible(find.byType(DResizableHandle));
    final widthBefore = tester
        .widget<DResizableHandle>(find.byType(DResizableHandle))
        .value;
    await tester.drag(find.byType(DResizableHandle), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<DResizableHandle>(find.byType(DResizableHandle)).value,
      greaterThan(widthBefore),
    );
    expect(_visibleValues(tester), List.generate(25, (index) => index + 26));
    expect(tester.takeException(), isNull);
  });
}

List<int> _visibleValues(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: find.byType(DTableCell), matching: find.byType(Text)),
    )
    .map((text) => int.parse(text.data!))
    .toList();
