import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/cooked_document.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/cooked_table.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/shell/progressive_html_mode.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html_parser;

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
  RenderMode renderMode = RenderMode.column,
  ValueChanged<SelectedContent?>? onSelectionChanged,
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
                onSelectionChanged: onSelectionChanged,
                child: CookedHtml(
                  html: html,
                  post: post,
                  siteUrl: 'https://source.example.com',
                  buildAsync: false,
                  renderMode: renderMode,
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
  testWidgets('large progressive tables bound mounted cells and page every row', (
    tester,
  ) async {
    final html =
        '<table><tr><th>Name</th><th>Notes</th></tr>'
        '${List.generate(500, (i) => '<tr><td>Member $i</td><td>Notes $i</td></tr>').join()}'
        '</table>';
    await _pump(tester, html, renderMode: const ProgressiveHtmlMode());

    expect(find.byType(CookedHtml).evaluate().length, 51);
    expect(_text('Member 499'), findsNothing);
    final semantics = tester.ensureSemantics();
    try {
      final visited = <String>{};
      for (var page = 0; page < 20; page++) {
        for (var row = page * 25; row < (page + 1) * 25; row++) {
          expect(_text('Member $row'), findsOneWidget);
          visited.add('Member $row');
        }
        expect(find.byType(CookedHtml).evaluate().length, 51);
        final last = _text('Member ${(page + 1) * 25 - 1}');
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(last).label, contains('Member'));
        final next = find.byType(DPaginationNext);
        await tester.ensureVisible(next);
        await tester.pumpAndSettle();
        if (page < 19) {
          await tester.tap(next);
          await tester.pumpAndSettle();
        } else {
          expect(tester.widget<DPaginationNext>(next).onPressed, isNull);
        }
        expect(tester.takeException(), isNull);
      }
      expect(visited, hasLength(500));
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is DPaginationLink && widget.page == 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(_text('Member 0'), findsOneWidget);
      expect(_text('Member 499'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('later pages retain rich cells, selection, sorting and full copy', (
    tester,
  ) async {
    String? copied;
    String? selected;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final html =
        '<table><tr><th>Name</th><th>Notes</th></tr>'
        '${List.generate(30, (i) => '<tr><td>Member $i</td><td><a href="/t/example/12">Link $i</a> <code>code $i</code></td></tr>').join()}'
        '</table>';
    await _pump(
      tester,
      html,
      onSelectionChanged: (content) => selected = content?.plainText,
    );
    await tester.ensureVisible(find.byType(DPaginationNext));
    await tester.tap(find.byType(DPaginationNext));
    await tester.pumpAndSettle();
    expect(_text('Member 29'), findsOneWidget);
    expect(find.byType(InlineCode), findsNWidgets(5));
    final linkCell = tester
        .widgetList<HtmlWidget>(find.byType(HtmlWidget))
        .firstWhere(
          (widget) =>
              widget.html.startsWith('<div>') &&
              widget.html.contains('Link 29'),
        );
    expect(linkCell.baseUrl, Uri.parse('https://source.example.com'));
    expect(linkCell.onTapUrl, isNotNull);
    tester
        .state<SelectionAreaState>(find.byType(SelectionArea))
        .selectableRegion
        .selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    expect(selected, contains('Member 29'));
    expect(selected, contains('code 29'));

    await tester.ensureVisible(find.text('Name'));
    await _sort(tester, 'Name', 'descending');
    expect(
      tester
          .widget<DPaginationNavigation>(find.byType(DPaginationNavigation))
          .page,
      1,
    );
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide column'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DPaginationNext));
    await tester.tap(find.byType(DPaginationNext));
    await tester.pumpAndSettle();
    final copy = find.byWidgetPredicate(
      (widget) => widget is DButton && widget.tooltip == 'Copy table',
    );
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pump();
    expect(
      copied,
      startsWith(
        '| Name | Notes |\n| --- | --- |\n| Member 0 | Link 0 code 0 |',
      ),
    );
    expect(copied, endsWith('| Member 29 | Link 29 code 29 |'));
    expect(copied!.split('\n'), hasLength(32));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'initial widths bound shaping and cache until layout inputs change',
    (tester) async {
      var scaleCalls = 0;
      var theme = AppTheme.dark;
      var direction = TextDirection.ltr;
      var textScaler = _CountingTextScaler(onScale: () => scaleCalls++);
      var value = 'cell';
      var rowCount = 500;
      Future<void> pumpTable() async {
        final html =
            '<table><tr><th>Name</th><th>Notes</th></tr>'
            '${List.generate(rowCount, (i) => '<tr><td>$value $i</td><td>note $i</td></tr>').join()}</table>';
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: MediaQueryData(textScaler: textScaler),
              child: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Builder(
                      builder: (context) => cookedTableWidgetBuilder(
                        html_parser.parseFragment(html).querySelector('table')!,
                        content: CookedDocument(html).bind(
                          (_, fragment, style) => const SizedBox(height: 1),
                        ),
                      )!,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final count in [50, 500, 5000]) {
        rowCount = count;
        scaleCalls = 0;
        await pumpTable();
        expect(
          scaleCalls,
          inExclusiveRange(0, 500),
          reason: 'Initial shaping must stay bounded with $count source rows',
        );
      }
      final initialCalls = scaleCalls;
      scaleCalls = 0;
      await pumpTable();
      final cachedBuildCalls = scaleCalls;
      expect(cachedBuildCalls, lessThan(initialCalls));
      scaleCalls = 0;
      await _sort(tester, 'Name', 'descending');
      expect(scaleCalls, lessThan(initialCalls));
      scaleCalls = 0;
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide column'));
      await tester.pumpAndSettle();
      expect(scaleCalls, lessThan(initialCalls));
      scaleCalls = 0;
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is DButton && widget.tooltip == 'Copy table',
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(scaleCalls, lessThan(initialCalls));
      scaleCalls = 0;
      direction = TextDirection.rtl;
      await pumpTable();
      expect(scaleCalls, inExclusiveRange(cachedBuildCalls, 500));
      scaleCalls = 0;
      theme = theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyMedium!.copyWith(fontSize: 16),
        ),
      );
      await pumpTable();
      expect(scaleCalls, inExclusiveRange(cachedBuildCalls, 500));
      scaleCalls = 0;
      textScaler = _CountingTextScaler(factor: 2, onScale: () => scaleCalls++);
      await pumpTable();
      expect(scaleCalls, inExclusiveRange(cachedBuildCalls, 500));
      scaleCalls = 0;
      value = 'changed';
      await pumpTable();
      expect(scaleCalls, inExclusiveRange(cachedBuildCalls, 500));
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(
      tester
          .widgetList<DDataTableColumnHeader>(
            find.byType(DDataTableColumnHeader),
          )
          .map((header) => header.size),
      everyElement(DControlSize.post),
    );
    expect(
      tester
          .widget<DDataTableColumnToggle<int>>(
            find.byType(DDataTableColumnToggle<int>),
          )
          .size,
      DControlSize.post,
    );
    expect(
      tester
          .widget<DButton>(
            find.byWidgetPredicate(
              (widget) => widget is DButton && widget.tooltip == 'Copy table',
            ),
          )
          .size,
      DButtonSize.post,
    );
    final copyButton = find.byWidgetPredicate(
      (widget) => widget is DButton && widget.tooltip == 'Copy table',
    );
    final paintedCopy = tester.widget<FilledButton>(
      find.descendant(of: copyButton, matching: find.byType(FilledButton)),
    );
    expect(paintedCopy.style!.fixedSize!.resolve({}), const Size(30, 30));
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
        final html = _html
            .replaceFirst('First note', note)
            .replaceFirst(
              '</tbody>',
              '${List.generate(27, (i) => '<tr><td>Member ${i + 3}</td><td>1</td><td>Note</td></tr>').join()}</tbody>',
            );
        await _pump(tester, html, scale: 2, direction: direction);
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
        await tester.ensureVisible(find.byType(DPaginationNext));
        await tester.tap(find.byType(DPaginationNext));
        await tester.pumpAndSettle();
        expect(_text('Member 29'), findsOneWidget);
        expect(_text(note), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets(
      'later long cells wrap within sampled widths at 200% text in $direction',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const note =
            'Staying at Artrip Hotel until the 24th then train to Seville';
        final html =
            '<table><tr><th>Name</th><th>Days</th><th>Notes</th></tr>'
            '${List.generate(30, (i) => '<tr><td>Member $i</td><td>1</td><td>${i == 29 ? '<strong>$note</strong>' : 'Note'}</td></tr>').join()}'
            '</table>';
        await _pump(tester, html, scale: 2, direction: direction);
        final widths = tester
            .widget<DDataTable<int>>(find.byType(DDataTable<int>))
            .columns
            .map((column) => (column.width as FixedColumnWidth).value)
            .toList();
        expect(widths.last, lessThan(360));
        expect(_text(note), findsNothing);
        final horizontal = tester
            .stateList<ScrollableState>(find.byType(Scrollable))
            .firstWhere(
              (state) =>
                  axisDirectionToAxis(state.axisDirection) == Axis.horizontal,
            );
        expect(horizontal.position.maxScrollExtent, greaterThan(0));
        await tester.ensureVisible(find.byType(DPaginationNext));
        await tester.tap(find.byType(DPaginationNext));
        await tester.pumpAndSettle();
        horizontal.position.jumpTo(horizontal.position.maxScrollExtent);
        await tester.pumpAndSettle();
        final longCell = _text(note);
        expect(longCell, findsOneWidget);
        await tester.ensureVisible(longCell);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(longCell);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.height, greaterThan(80));
        expect(paragraph.size.width, lessThanOrEqualTo(widths.last));
        expect(
          tester
              .widget<DDataTable<int>>(find.byType(DDataTable<int>))
              .columns
              .map((column) => (column.width as FixedColumnWidth).value),
          widths,
        );
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

class _CountingTextScaler extends TextScaler {
  const _CountingTextScaler({required this.onScale, this.factor = 1});

  final double factor;
  final VoidCallback onScale;

  @override
  double scale(double fontSize) {
    onScale();
    return fontSize * factor;
  }

  @override
  double get textScaleFactor => factor;
}
