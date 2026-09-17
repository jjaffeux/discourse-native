import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

const _html = '''
<table><thead><tr><th>Who?</th><th>Days</th><th>Notes</th></tr></thead>
<tbody>
<tr><td>Zara</td><td>10</td><td><strong>First note</strong></td></tr>
<tr><td>Abe</td><td>2</td><td><code>second</code></td></tr>
<tr><td>Mina</td><td>2</td><td>Third note</td></tr>
</tbody></table>
''';

Future<void> _pump(
  WidgetTester tester,
  String html, {
  Post? post,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: SingleChildScrollView(
              child: SelectionArea(
                child: CookedHtml(
                  html: html,
                  post: post,
                  siteUrl: 'https://source.example.com',
                  buildAsync: false,
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

Finder _text(String text) => find.text(text, findRichText: true);

Future<void> _sort(WidgetTester tester, String column, String order) async {
  await tester.tap(find.text(column));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sort $order'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('copy table copies complete Markdown beside Columns', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester, _html);
    await _sort(tester, 'Days', 'ascending');
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide column'));
    await tester.pumpAndSettle();
    final copy = find.byWidgetPredicate(
      (w) => w is DButton && w.tooltip == 'Copy table',
    );
    expect(copy, findsOneWidget);
    expect(find.text('Columns'), findsOneWidget);
    await tester.tap(copy);
    await tester.pump();
    expect(
      copied,
      '| Who? | Days | Notes |\n| --- | --- | --- |\n| Zara | 10 | First note |\n| Abe | 2 | second |\n| Mina | 2 | Third note |',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is DButton && w.tooltip == 'Table copied',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(copy, findsOneWidget);

    await _pump(
      tester,
      r'<table><tr><th>Text</th></tr><tr><td>A|B<br>C\D</td></tr></table>',
    );
    await tester.tap(copy);
    await tester.pump();
    expect(
      copied,
      '| Text |\n| --- |\n'
      r'| A\|B<br>C\\D |',
    );
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'renders every row and keeps rich cells and the source link context',
    (tester) async {
      final html =
          '<table><thead><tr><th>Name</th><th>Notes</th></tr></thead><tbody>'
          '${List.generate(13, (i) => '<tr><td>Member $i</td><td><a class="track-link" href="/t/example/12">Link $i</a> <code>code $i</code></td></tr>').join()}'
          '</tbody></table>';
      await _pump(
        tester,
        html,
        post: const Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '',
          linkCounts: [
            PostLinkCount(url: '/t/example/12', clicks: 7, internal: true),
          ],
        ),
      );

      expect(find.byType(DDataTable<int>), findsOneWidget);
      expect(_text('Member 12'), findsOneWidget);
      expect(find.byType(InlineCode), findsNWidgets(13));
      final cell = tester
          .widgetList<HtmlWidget>(find.byType(HtmlWidget))
          .firstWhere(
            (widget) =>
                widget.html.startsWith('<div>') &&
                widget.html.contains('Link 0'),
          );
      expect(cell.baseUrl, Uri.parse('https://source.example.com'));
      expect(find.textContaining('Link 0', findRichText: true), findsOneWidget);
      expect(
        tester
            .widgetList<RichText>(find.byType(RichText))
            .where((widget) => widget.text.toPlainText() == '7'),
        isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sorts numerically and stably, hides and restores columns, and resizes locally',
    (tester) async {
      await _pump(tester, _html);
      await _sort(tester, 'Days', 'ascending');
      expect(
        tester.getTopLeft(_text('Abe')).dy,
        lessThan(tester.getTopLeft(_text('Mina')).dy),
      );
      expect(
        tester.getTopLeft(_text('Mina')).dy,
        lessThan(tester.getTopLeft(_text('Zara')).dy),
      );
      await _sort(tester, 'Who?', 'descending');
      expect(
        tester.getTopLeft(_text('Zara')).dy,
        lessThan(tester.getTopLeft(_text('Mina')).dy),
      );

      final before = tester.getSize(find.byType(DTableHead).first).width;
      await tester.drag(
        find.byType(DResizableHandle).first,
        const Offset(55, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(DTableHead).first).width,
        greaterThan(before + 30),
      );
      final resized = tester.getSize(find.byType(DTableHead).first).width;

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide column'));
      await tester.pumpAndSettle();
      expect(_text('First note'), findsNothing);
      await tester.tap(find.text('Columns'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 580));
      await tester.pumpAndSettle();
      expect(_text('First note'), findsOneWidget);
      expect(tester.getSize(find.byType(DTableHead).first).width, resized);

      await _pump(tester, _html, theme: AppTheme.light);
      expect(tester.getSize(find.byType(DTableHead).first).width, resized);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, _html);
      expect(tester.getSize(find.byType(DTableHead).first).width, before);
      expect(
        tester.getTopLeft(_text('Zara')).dy,
        lessThan(tester.getTopLeft(_text('Abe')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'wraps long notes and scrolls at 320px with 200% text in $direction',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const note =
            'Staying at Artrip Hotel until the 24th then train to Seville';
        await _pump(
          tester,
          _html.replaceFirst('First note', note),
          scale: 2,
          direction: direction,
        );
        expect(tester.getSize(_text(note)).height, greaterThan(40));
        final horizontal = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .firstWhere(
              (state) =>
                  axisDirectionToAxis(state.axisDirection) == Axis.horizontal,
            );
        expect(horizontal.position.maxScrollExtent, greaterThan(0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position:
                tester.getTopLeft(find.byType(DDataTable<int>)) +
                const Offset(80, 120),
            scrollDelta: Offset(direction == TextDirection.rtl ? -150 : 150, 0),
          ),
        );
        await tester.pumpAndSettle();
        expect(horizontal.position.pixels, greaterThan(0));
        horizontal.position.jumpTo(horizontal.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sorts mixed numeric and text values consistently', (
    tester,
  ) async {
    await _pump(
      tester,
      _html.replaceFirst('<td>Mina</td><td>2</td>', '<td>Mina</td><td>1a</td>'),
    );
    await _sort(tester, 'Days', 'ascending');
    expect(
      tester.getTopLeft(_text('Abe')).dy,
      lessThan(tester.getTopLeft(_text('Zara')).dy),
    );
    expect(
      tester.getTopLeft(_text('Zara')).dy,
      lessThan(tester.getTopLeft(_text('Mina')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('edited table content resets local state and keeps captions', (
    tester,
  ) async {
    await _pump(tester, _html);
    await _sort(tester, 'Who?', 'ascending');
    final edited = _html
        .replaceFirst('<table>', '<table><caption>Trip notes</caption>')
        .replaceAll('Zara', 'Zoe');
    await _pump(tester, edited);
    expect(
      tester.getTopLeft(_text('Zoe')).dy,
      lessThan(tester.getTopLeft(_text('Abe')).dy),
    );
    expect(find.byType(DTableCaption), findsOneWidget);
    expect(_text('Trip notes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preserves complex table content with its existing renderer', (
    tester,
  ) async {
    for (final html in [
      '<table><tr><th colspan="2">Merged header</th></tr><tr><td>A</td><td>B</td></tr></table>',
      '<table><tr><th>Header</th></tr><tr><td rowspan="2">Merged rows</td></tr><tr></tr></table>',
      '<table><tr><th><a href="/faq">Linked header</a></th></tr><tr><td>Value</td></tr></table>',
      '<table><tr><td>Headerless</td></tr></table>',
    ]) {
      await _pump(tester, html);
      expect(find.byType(DDataTable<int>), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('keeps separate state for duplicate headers and separate tables', (
    tester,
  ) async {
    await _pump(
      tester,
      '$_html${_html.replaceAll('Who?', 'Days').replaceAll('Zara', 'Other Zara')}',
    );
    await tester.tap(find.text('Who?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide column'));
    await tester.pumpAndSettle();
    expect(_text('Zara'), findsNothing);
    expect(_text('Other Zara'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
