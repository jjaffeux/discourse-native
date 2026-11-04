import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_document.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;

void main() {
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets(
        'sampled column widths retain text metrics ($direction, $scale)',
        (tester) async {
          final values = [
            ['', 'short', 'short'],
            ['Heading', 'a medium length entry', 'another entry'],
            ['Wide heading ${'W' * 60}', 'narrow'],
            ['Unicode', 'François café', '日本語の文章', '👨‍👩‍👧‍👦 ⛵️'],
            ['Mixed', 'العربية 123 abc', 'abc עברית 123', '\u202eabc 123'],
            ['Whitespace', '  a\t b\n c  ', 'A\u00a0B', 'C\u2028D'],
            ['Threshold', 'w' * 28, 'w' * 29, 'w' * 30],
            ['Long cell', 'very long entry ' * 60],
          ];
          final table = dom.Element.tag('table');
          final header = dom.Element.tag('tr');
          table.append(header);
          for (final column in values) {
            header.append(dom.Element.tag('th')..text = column.first);
          }
          for (var row = 1; row < 30; row++) {
            final tr = dom.Element.tag('tr');
            for (final column in values) {
              tr.append(
                dom.Element.tag('td')
                  ..text = row < column.length ? column[row] : column.last,
              );
            }
            table.append(tr);
          }
          final style = AppTheme.light.textTheme.bodyMedium!.copyWith(
            letterSpacing: .3,
            wordSpacing: .6,
          );
          final scaler = TextScaler.linear(scale);
          final expected = <double>[];
          for (var column = 0; column < values.length; column++) {
            var width = 140.0;
            final painter = TextPainter(
              textDirection: direction,
              textScaler: scaler,
              maxLines: 1,
            );
            try {
              for (final row in table.children.take(26)) {
                painter.text = TextSpan(
                  text: CookedTableCell(row.children[column]).text,
                  style: style,
                );
                painter.layout(maxWidth: 320);
                width = math.max(width, painter.width + 48);
                if (width >= 360) {
                  width = 360;
                  break;
                }
              }
              expected.add(width);
            } finally {
              painter.dispose();
            }
          }
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light.copyWith(
                textTheme: AppTheme.light.textTheme.copyWith(bodyMedium: style),
              ),
              home: MediaQuery(
                data: MediaQueryData(textScaler: scaler),
                child: Directionality(
                  textDirection: direction,
                  child: SingleChildScrollView(
                    child: Builder(
                      builder: (context) => cookedTableWidgetBuilder(
                        table,
                        content: CookedDocument(
                          table.outerHtml,
                        ).bind((_, _, _) => const SizedBox(height: 1)),
                      )!,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final columns = tester
              .widget<DDataTable<int>>(find.byType(DDataTable<int>))
              .columns;
          for (var column = 0; column < columns.length; column++) {
            expect(
              (columns[column].width as FixedColumnWidth).value,
              closeTo(expected[column], .001),
              reason: 'Column $column',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
