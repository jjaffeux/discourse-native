import 'dart:async';

import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _body =
    '<p>Outer paragraph.</p><blockquote><p>Quoted paragraph.</p>'
    '<table><tr><th>Heading</th></tr><tr><td><strong>Rich cell.</strong></td></tr></table>'
    '</blockquote>';

Finder _text(String value) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(value),
);

Widget _host({
  required bool deferred,
  ValueChanged<SelectedContent?>? selected,
  bool Function(HtmlBodyMountingNotification)? onMounting,
}) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: SelectionArea(
      onSelectionChanged: selected,
      child: SingleChildScrollView(
        child: HtmlBodyTiming(
          followsFrame: deferred,
          child: NotificationListener<HtmlBodyMountingNotification>(
            onNotification: onMounting,
            child: const CookedHtml(html: _body, buildAsync: false),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('disposing a deferred quote releases its loading completion', (
    tester,
  ) async {
    final pending = <Future<void>>{};
    await tester.pumpWidget(
      _host(
        deferred: true,
        onMounting: (notification) {
          pending.add(notification.completion);
          unawaited(
            notification.completion.whenComplete(
              () => pending.remove(notification.completion),
            ),
          );
          return false;
        },
      ),
    );
    expect(pending, isNotEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(pending, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary opening renders nested quotes in the opening frame', (
    tester,
  ) async {
    await tester.pumpWidget(_host(deferred: false));
    expect(_text('Outer paragraph.'), findsOneWidget);
    expect(_text('Quoted paragraph.'), findsOneWidget);
    expect(find.byType(CookedTable), findsOneWidget);
    expect(_text('Rich cell.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deferred replies yield before rendering nested quoted bodies', (
    tester,
  ) async {
    final pending = <Future<void>>{};
    String? selected;
    await tester.pumpWidget(
      _host(
        deferred: true,
        selected: (value) => selected = value?.plainText,
        onMounting: (notification) {
          pending.add(notification.completion);
          unawaited(
            notification.completion.whenComplete(
              () => pending.remove(notification.completion),
            ),
          );
          return false;
        },
      ),
    );
    expect(_text('Outer paragraph.'), findsOneWidget);
    final quote = tester.element(find.byType(QuoteBlock));
    expect(_text('Quoted paragraph.'), findsNothing);
    expect(find.byType(CookedTable), findsNothing);
    expect(pending, isNotEmpty);
    for (var i = 0; i < 100 && _text('Rich cell.').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(Duration.zero);
    }
    expect(_text('Quoted paragraph.'), findsOneWidget);
    expect(_text('Rich cell.'), findsOneWidget);
    expect(find.byType(CookedTable), findsOneWidget);
    expect(tester.element(find.byType(QuoteBlock)), same(quote));
    await tester.pump();
    expect(pending, isEmpty);
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea))
        .selectableRegion
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(selected, contains('Outer paragraph.'));
    expect(selected, contains('Quoted paragraph.'));
    expect(selected, contains('Rich cell.'));
    expect(tester.takeException(), isNull);
  });
}
