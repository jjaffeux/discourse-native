import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

Future<void> _pump(
  WidgetTester tester,
  String html, {
  bool narrow = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: narrow ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: narrow ? 300 : 700,
            child: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(narrow ? 2 : 1),
              ),
              child: SingleChildScrollView(
                child: SelectionArea(
                  child: CookedHtml(
                    html: html,
                    textStyle: const TextStyle(fontSize: 19, height: 1.6),
                    siteUrl: 'https://example.test',
                    buildAsync: false,
                  ),
                ),
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
  testWidgets('details collapse, expand and keep rich body and site context', (
    tester,
  ) async {
    await _pump(
      tester,
      '<p>Before</p><details><summary>Read more</summary><p><a href="/t/topic/1">Topic</a> <code>code</code></p></details><p>After</p>',
    );
    expect(find.byType(DAccordion<int>), findsOneWidget);
    expect(find.text('Before', findRichText: true), findsOneWidget);
    expect(find.byType(InlineCode), findsNothing);
    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    expect(find.byType(InlineCode), findsOneWidget);
    final nested = tester.widgetList<HtmlWidget>(find.byType(HtmlWidget)).last;
    expect(nested.baseUrl, Uri.parse('https://example.test'));
    expect(nested.textStyle?.fontSize, 19);
    expect(nested.textStyle?.height, 1.6);
    expect(find.textContaining('Topic', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    expect(find.byType(InlineCode), findsNothing);
  });

  testWidgets('open and nested details have independent keyboard disclosure', (
    tester,
  ) async {
    await _pump(
      tester,
      '<details open><summary>Outer</summary><p>Visible</p><details><summary>Inner</summary><p>Nested</p></details></details>',
    );
    expect(find.text('Visible', findRichText: true), findsOneWidget);
    expect(find.text('Nested', findRichText: true), findsNothing);
    await tester.tap(find.text('Inner'));
    await tester.pumpAndSettle();
    expect(find.text('Nested', findRichText: true), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Nested', findRichText: true), findsNothing);
    expect(find.text('Visible', findRichText: true), findsOneWidget);
  });

  testWidgets(
    'empty summaries fall back and long summaries wrap in dark narrow layouts',
    (tester) async {
      await _pump(
        tester,
        '<details><summary></summary><p>Body</p></details><details><summary>A long summary which should wrap across several lines without overflowing</summary><p>More</p></details>',
        narrow: true,
      );
      expect(find.text('Details'), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Body', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
