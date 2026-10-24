import 'dart:collection';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart' as editor;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const String blobOnebox = '''
<aside class="onebox githubblob" data-onebox-src="https://github.com/discourse/discourse/blob/290ee31/app/models/upload.rb#L78-L80">
  <header class="source">
      <a href="https://github.com/discourse/discourse" target="_blank" rel="noopener">github.com/discourse/discourse</a>
  </header>
  <article class="onebox-body">
    <h4><a href="https://github.com/discourse/discourse" target="_blank" rel="noopener">app/models/upload.rb</a></h4>
<div class="git-blob-info">
  <a href="https://github.com/discourse/discourse" rel="noopener"><code>290ee312e</code></a>
</div>
    <pre class="onebox"><code class="lang-rb">
      <ol class="start lines" start="78" style="counter-reset: li-counter 77 ;">
          <li>def self.get_from_url(url)</li>
          <li class="selected">  return if url.blank?</li>
          <li></li>
          <li>end</li>
      </ol>
    </code></pre>
  </article>
</aside>
''';

const String codeFence = '''
<pre><code class="lang-ruby">def hello
  puts "hi"
end
</code></pre>
''';

CodeBlockData parseBlock(String source) {
  final pre = html.parse(source).querySelector('pre')!;
  return CodeBlockData.from(pre);
}

bool paintsKeyword(WidgetTester tester, Finder line) {
  var found = false;
  tester.widget<Text>(line).textSpan!.visitChildren((span) {
    if (span is TextSpan && span.style?.color == CodeColors.light.keyword) {
      found = true;
    }
    return true;
  });
  return found;
}

/// Deferred highlighting parses on a real isolate, which the fake clock does
/// not drive.
Future<void> pumpUntilKeywordPainted(WidgetTester tester, Finder line) async {
  for (
    var attempt = 0;
    attempt < 100 && !paintsKeyword(tester, line);
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  group('CodeBlockData', () {
    test('reads a git blob onebox as numbered lines', () {
      final lines = parseBlock(blobOnebox).lines;

      expect(lines.length, 4);
      expect(lines.first.text, 'def self.get_from_url(url)');
      expect(lines.first.number, 78);
      expect(lines.last.number, 81);
      expect(lines[2].text, isEmpty);
    });

    test('keeps indentation, which is the whole point of a code block', () {
      expect(parseBlock(blobOnebox).lines[1].text, '  return if url.blank?');
    });

    test('source copy preserves authored whitespace boundaries', () {
      for (final source in [
        '\n  - first \t\n\t- second  \n \t\n\n',
        '\n \t\n',
      ]) {
        final data = CodeBlockData.fromSource(source, language: 'text');

        expect(data.text, source);
        expect(data.clipboardText, source);
      }
    });

    test('copy normalizes unusual whitespace without discarding it', () {
      const unusual = [
        '\f',
        '\v',
        '\u00a0',
        '\u1680',
        '\u2000',
        '\u2001',
        '\u2002',
        '\u2003',
        '\u2004',
        '\u2005',
        '\u2006',
        '\u2007',
        '\u2008',
        '\u2009',
        '\u200a',
        '\u202f',
        '\u205f',
        '\u3000',
        '\ufeff',
      ];
      for (final whitespace in unusual) {
        final source = '$whitespace\t value$whitespace\n';
        final data = CodeBlockData.fromSource(source, language: 'text');

        expect(data.text, source);
        expect(data.clipboardText, ' \t value \n');
      }
    });

    test('marks the lines the link pointed at', () {
      final lines = parseBlock(blobOnebox).lines;

      expect(lines[1].isSelected, isTrue);
      expect(lines[0].isSelected, isFalse);
    });

    test('reads the language off the code element', () {
      expect(parseBlock(blobOnebox).language, 'rb');
      expect(parseBlock(codeFence).language, 'ruby');
      expect(parseBlock('<pre><code>x</code></pre>').language, isNull);
    });

    test('highlights, without disturbing the lines or their numbers', () {
      final lines = parseBlock(blobOnebox).lines;

      expect(lines.first.tokens.any((token) => token.scope != null), isTrue);
      expect(lines.length, 4);
      expect(lines.first.number, 78);
      expect(lines.first.text, 'def self.get_from_url(url)');
      expect(lines[1].isSelected, isTrue);
    });

    test('reads an ordinary code fence, unnumbered', () {
      final lines = parseBlock(codeFence).lines;

      expect(lines.map((line) => line.text), [
        'def hello',
        '  puts "hi"',
        'end',
      ]);
      expect(lines.every((line) => line.number == null), isTrue);
    });

    test('drops the newlines the tags contribute, not the code', () {
      // `<pre>` swallows one newline after the open tag; the fence adds one
      // before the close. Neither is a line anybody wrote.
      final lines = parseBlock('<pre><code>\nonly\n</code></pre>').lines;

      expect(lines.map((line) => line.text), ['only']);
    });

    test('keeps the blank lines the author wrote', () {
      // One newline at each end is the markup's; everything past that is
      // spacing somebody typed, and a fence that ends on it kept it.
      final lines = parseBlock('<pre><code>\na\n\nb\n\n\n</code></pre>').lines;

      expect(lines.map((line) => line.text), ['a', '', 'b', '', '']);
    });
  });

  group('CodeBlock', () {
    for (final numbered in [false, true]) {
      testWidgets('inline and fullscreen copy preserve authored whitespace '
          '(numbered: $numbered)', (tester) async {
        const source = '\n  - first \t\n\t- second  \n \t\n';
        final markup = numbered
            ? '<pre><code><ol start="12">'
                  '${source.split('\n').map((line) => '<li>$line</li>').join()}'
                  '</ol></code></pre>'
            : '<pre><code>\n$source\n</code></pre>';
        final data = parseBlock(markup);
        expect(data.text, source);
        final copied = <String>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String,
            );
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: CodeBlock(data: data)),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('code-block-copy')));
        await tester.pump();
        expect(copied, [source]);

        await tester.tap(find.byKey(const ValueKey('code-block-fullscreen')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('code-block-copy')));
        await tester.pump();
        expect(copied, [source, source]);

        await tester.tap(
          find.byKey(const ValueKey('code-block-fullscreen-close')),
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('long fences retain complete copy and fullscreen source', (
      tester,
    ) async {
      final source = List.generate(
        5000,
        (index) => '  value $index',
      ).join('\n');
      String? copied;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DScrollArea(
              child: CodeBlock(
                data: CodeBlockData.fromSource(source, language: 'text'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DCodeViewer), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('code-block-copy')));
      await tester.pump();
      expect(copied, source);
      await tester.tap(find.byKey(const ValueKey('code-block-fullscreen')));
      await tester.pumpAndSettle();
      final field = tester.widget<editor.CodeField>(
        find.byType(editor.CodeField),
      );
      expect(field.controller.text, source);
      expect(field.readOnly, isTrue);
      await tester.tap(
        find.byKey(const ValueKey('code-block-fullscreen-close')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DCodeViewer), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'long numbered fences pass original line metadata to the viewer',
      (tester) async {
        final lines = List.generate(
          500,
          (index) => CodeLine(
            tokens: [
              CodeToken(index == 1 ? 'value 1\ncontinued' : 'value $index'),
            ],
            number: index == 1 ? null : index - 300,
            isSelected: index == 2 || index == 499,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: DScrollArea(
                child: CodeBlock(data: CodeBlockData(lines: lines)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final viewer = tester.widget<DCodeViewer>(find.byType(DCodeViewer));
        expect(viewer.lineNumbers, [
          -300,
          null,
          null,
          ...List.generate(498, (index) => index - 298),
        ]);
        expect(viewer.highlightedLines, {3, 500});
        expect(viewer.lineSpanBuilder!(2).toPlainText(), 'continued');
        expect(viewer.source, endsWith('value 499'));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('hard-break rows retain token styles and numbered metadata', (
      tester,
    ) async {
      final lines = [
        const CodeLine(
          tokens: [CodeToken('alpha\r', 'keyword')],
          number: 78,
          isSelected: true,
        ),
        const CodeLine(
          tokens: [
            CodeToken('beta\u2028gam', 'string'),
            CodeToken('ma\vdelta\r', 'comment'),
            CodeToken('\nepsilon', 'number'),
          ],
          number: 79,
        ),
        ...List.generate(
          110,
          (index) =>
              CodeLine(tokens: [CodeToken('tail $index')], number: index + 80),
        ),
      ];
      final data = CodeBlockData(lines: lines);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DScrollArea(child: CodeBlock(data: data)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<DCodeViewer>(find.byType(DCodeViewer));
      expect(viewer.source, data.text);
      expect(viewer.lineNumbers!.take(6), [78, 79, null, null, null, 80]);
      expect(viewer.highlightedLines, {0});
      expect(viewer.lineSpanBuilder!(0).toPlainText(), 'alpha');
      expect(viewer.lineSpanBuilder!(1).toPlainText(), 'beta');
      expect(viewer.lineSpanBuilder!(2).toPlainText(), 'gamma');
      expect(viewer.lineSpanBuilder!(3).toPlainText(), 'delta');
      expect(viewer.lineSpanBuilder!(4).toPlainText(), 'epsilon');
      final gamma = viewer.lineSpanBuilder!(2) as TextSpan;
      expect(gamma.children!.length, 2);
      expect(
        gamma.children![0].style!.color,
        isNot(gamma.children![1].style!.color),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('one numbered item with many physical lines is virtualized', (
      tester,
    ) async {
      final source = List.generate(1000, (index) => 'row $index').join('\n');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: DScrollArea(
              child: CodeBlock(
                data: CodeBlockData(
                  lines: [
                    CodeLine(
                      tokens: [CodeToken(source)],
                      number: 78,
                      isSelected: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<DCodeViewer>(find.byType(DCodeViewer));
      expect(viewer.source, source);
      expect(viewer.lineNumbers!.length, 1000);
      expect(viewer.lineNumbers!.first, 78);
      expect(viewer.lineNumbers!.skip(1), everyElement(isNull));
      expect(viewer.highlightedLines.length, 1000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header fits a narrow chat bubble without losing its actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 125,
                child: CodeBlock(data: parseBlock(codeFence)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Copy code'), findsOneWidget);
      expect(find.byTooltip('View code full screen'), findsOneWidget);
    });

    for (final numbered in [false, true]) {
      for (final count in [20, 100, 500, 1000]) {
        testWidgets(
          'line metadata reads stay linear ($count, numbered: $numbered)',
          (tester) async {
            final markup = numbered
                ? '<pre><code class="lang-text"><ol start="98">${List.generate(count, (i) => '<li>value $i</li>').join()}</ol></code></pre>'
                : '<pre><code class="lang-text">${List.generate(count, (i) => 'value $i').join('\n')}</code></pre>';
            final parsed = parseBlock(markup);
            final lines = _CountingLines(parsed.lines);
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.light,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: CodeBlock(data: CodeBlockData(lines: lines)),
                  ),
                ),
              ),
            );
            // Reading clipboard text, gutter metadata and row data may each
            // traverse the list; no traversal may be repeated for every row.
            expect(lines.reads, lessThanOrEqualTo(count * 6));
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }

    testWidgets('mixed null and negative numbers share the widest gutter', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: CodeBlock(
              data: CodeBlockData(
                lines: [
                  CodeLine(tokens: [CodeToken('missing')]),
                  CodeLine(tokens: [CodeToken('negative')], number: -100),
                  CodeLine(tokens: [CodeToken('small')], number: 2),
                ],
              ),
            ),
          ),
        ),
      );
      for (final text in ['missing', 'negative', 'small']) {
        final row = tester.widget<Row>(
          find.ancestor(of: find.text(text), matching: find.byType(Row)).first,
        );
        expect((row.children.first as SizedBox).width, 44);
      }
    });

    testWidgets('gutter follows replacement data and theme rebuilds', (
      tester,
    ) async {
      Future<void> pump(String markup, ThemeData theme) => tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: CodeBlock(data: parseBlock(markup))),
        ),
      );
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await pump(
          '<pre><code class="lang-text"><ol start="98"><li>first</li>'
          '<li class="selected">second</li><li>third</li></ol></code></pre>',
          theme,
        );
        await tester.pumpAndSettle();
        final gutter = find
            .ancestor(of: find.text('100'), matching: find.byType(SizedBox))
            .first;
        expect(tester.getSize(gutter).width, 36);
        final selected = tester.widget<ColoredBox>(
          find
              .ancestor(
                of: find.text('second'),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(selected.color, theme.colorScheme.tertiaryContainer);
        await pump('<pre><code class="lang-text">plain</code></pre>', theme);
        expect(find.text('100'), findsNothing);
        final row = tester.widget<Row>(
          find
              .ancestor(of: find.text('plain'), matching: find.byType(Row))
              .first,
        );
        expect(row.children.length, 3);
      }
    });

    testWidgets('deferred tokens preserve gutter and selected line geometry', (
      tester,
    ) async {
      final data = parseBlock(
        '<pre><code class="lang-ruby"><ol start="98">'
        '${List.generate(100, (i) => '<li class="${i == 0 ? 'selected' : ''}">def example_$i = "value"</li>').join()}'
        '</ol></code></pre>',
      );
      expect(data.highlightDeferred, isTrue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: CodeBlock(data: data)),
          ),
        ),
      );
      final code = find.text('def example_0 = "value"');
      final before = tester.getRect(code);

      await pumpUntilKeywordPainted(tester, code);
      expect(paintsKeyword(tester, code), isTrue);
      expect(tester.getRect(code), before);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('197'),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .width,
        36,
      );
      expect(
        tester
            .widget<ColoredBox>(
              find.ancestor(of: code, matching: find.byType(ColoredBox)).first,
            )
            .color,
        AppTheme.light.colorScheme.tertiaryContainer,
      );
    });

    testWidgets('an unlabelled fence detects its language off the frame', (
      tester,
    ) async {
      // An unlabelled fence cooks to `lang-auto`, and detection parses it once
      // per candidate grammar: several times what a labelled block this size
      // may spend in place.
      clearSyntaxHighlightCacheForTesting();
      final source = List.generate(
        36,
        (i) => 'def auto_example_$i = "value"',
      ).join('\n');
      expect(source.length, greaterThanOrEqualTo(1000));
      expect(source.length, lessThan(backgroundSyntaxHighlightThreshold));

      final data = parseBlock(
        '<pre><code class="lang-auto">$source\n</code></pre>',
      );
      expect(data.highlightDeferred, isTrue);
      expect(
        data.lines.expand((line) => line.tokens).map((token) => token.scope),
        everyElement(isNull),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: CodeBlock(data: data)),
          ),
        ),
      );
      final code = find.text('def auto_example_0 = "value"');
      final before = tester.getRect(code);
      expect(paintsKeyword(tester, code), isFalse);

      await pumpUntilKeywordPainted(tester, code);
      expect(paintsKeyword(tester, code), isTrue);
      expect(tester.getRect(code), before);
      expect(highlightNeedsParse(source, 'auto'), isFalse);
    });

    testWidgets('draws every line, with its number', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(blobOnebox))),
        ),
      );

      expect(find.text('def self.get_from_url(url)'), findsOneWidget);
      expect(find.text('78'), findsOneWidget);
      expect(find.text('81'), findsOneWidget);
    });

    testWidgets('shows the language and flat actions in a header', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(codeFence))),
        ),
      );

      expect(find.text('Ruby'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.code,
        ),
        findsOneWidget,
      );

      for (final key in const [
        ValueKey('code-block-copy'),
        ValueKey('code-block-fullscreen'),
      ]) {
        expect(
          tester.widget<DButton>(find.byKey(key)).variant,
          DButtonVariant.ghost,
        );
      }

      expect(
        tester.getCenter(find.text('Ruby')).dy,
        lessThan(tester.getCenter(find.text('def hello').first).dy),
      );
    });

    testWidgets('paints keywords in the theme colour', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(codeFence))),
        ),
      );

      final line = tester.widget<Text>(find.text('def hello').first);
      final colors = <Color?>[];
      line.textSpan!.visitChildren((span) {
        if (span is TextSpan) colors.add(span.style?.color);
        return true;
      });

      expect(colors, contains(CodeColors.light.keyword));
    });

    testWidgets('uses the same code face as Discourse', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(codeFence))),
        ),
      );

      final line = tester.widget<Text>(find.text('def hello').first);
      expect(line.style?.fontFamily, monospaceTextStyle.fontFamily);
      expect(
        line.style?.fontFamilyFallback,
        monospaceTextStyle.fontFamilyFallback,
      );
      expect(line.style?.fontSize, DiscourseTypography.sm);
      expect(line.style?.height, DiscourseTypography.codeLineHeight);
      expect(line.style?.color, DiscourseColors.light.primaryVeryHigh);
      expect(
        line.style?.fontFeatures,
        contains(const FontFeature.disable('liga')),
      );
    });

    testWidgets('fills the width it is given, however short the code', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              // How HtmlWidget lays a post out: children keep their own width
              // unless they insist otherwise.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [CodeBlock(data: parseBlock(codeFence))],
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(CodeBlock)).width, 400);
    });

    testWidgets('has no border, matching Discourse core', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(codeFence))),
        ),
      );

      final block = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(CodeBlock),
              matching: find.byType(Container),
            ),
          )
          .singleWhere(
            (container) =>
                container.decoration is BoxDecoration &&
                (container.decoration! as BoxDecoration).color ==
                    CodeColors.light.blockBackground,
          );
      final decoration = block.decoration! as BoxDecoration;

      expect(decoration.border, isNull);
    });

    testWidgets('scrolls sideways rather than cutting a long line off', (
      tester,
    ) async {
      final long = 'x' * 400;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: CodeBlock(
                data: parseBlock('<pre><code>$long</code></pre>'),
              ),
            ),
          ),
        ),
      );

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollView.scrollDirection, Axis.horizontal);
      expect(scrollView.controller!.position.maxScrollExtent, greaterThan(0));
      expect(
        tester.widget<DScrollBar>(find.byType(DScrollBar)).thumbVisibility,
        isTrue,
      );
    });

    testWidgets('copies the source without line-number markup', (tester) async {
      String? clipboardText;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(blobOnebox))),
        ),
      );

      const copyButton = ValueKey('code-block-copy');
      expect(
        tester.widget<DButton>(find.byKey(copyButton)).tooltip,
        'Copy code',
      );
      await tester.tap(find.byKey(copyButton));
      await tester.pump();

      expect(
        clipboardText,
        'def self.get_from_url(url)\n'
        '  return if url.blank?\n\n'
        'end',
      );
      expect(tester.widget<DButton>(find.byKey(copyButton)).tooltip, 'Copied!');

      await tester.pump(const Duration(seconds: 3));
      expect(
        tester.widget<DButton>(find.byKey(copyButton)).tooltip,
        'Copy code',
      );
    });

    testWidgets('opens a full-screen viewer with copy and close controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(codeFence))),
        ),
      );

      const fullscreenButton = ValueKey('code-block-fullscreen');
      expect(
        tester.widget<DButton>(find.byKey(fullscreenButton)).tooltip,
        'View code full screen',
      );
      await tester.tap(find.byKey(fullscreenButton));
      await tester.pumpAndSettle();

      expect(find.byType(CodeBlockFullscreen), findsOneWidget);
      expect(find.text('Ruby'), findsOneWidget);
      expect(find.byKey(const ValueKey('code-block-copy')), findsOneWidget);
      expect(find.byKey(fullscreenButton), findsNothing);

      final editorField = tester.widget<editor.CodeField>(
        find.descendant(
          of: find.byKey(const ValueKey('code-block-fullscreen-editor')),
          matching: find.byType(editor.CodeField),
        ),
      );
      expect(editorField.readOnly, isTrue);
      expect(editorField.wrap, isFalse);
      expect(editorField.expands, isTrue);
      expect(editorField.controller.readOnly, isTrue);
      expect(editorField.controller.text, 'def hello\n  puts "hi"\nend');
      expect(editorField.controller.language, isNotNull);

      final close = find.byKey(const ValueKey('code-block-fullscreen-close'));
      final viewer = find.byKey(const ValueKey('code-block-fullscreen-view'));
      final language = find.byKey(
        const ValueKey('code-block-fullscreen-language'),
      );
      expect(
        tester.getRect(language).center.dx,
        moreOrLessEquals(tester.getRect(viewer).center.dx),
      );
      expect(
        tester.getRect(viewer).right - tester.getRect(close).right,
        lessThanOrEqualTo(8),
      );

      await tester.tap(close);
      await tester.pumpAndSettle();

      expect(find.byType(CodeBlockFullscreen), findsNothing);
      expect(
        tester.widget<DButton>(find.byKey(fullscreenButton)).tooltip,
        'View code full screen',
      );
    });

    testWidgets('closes the full-screen viewer on Escape', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CodeBlock(data: parseBlock(codeFence))),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('code-block-fullscreen')));
      await tester.pumpAndSettle();
      expect(find.byType(CodeBlockFullscreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CodeBlockFullscreen), findsNothing);
    });

    testWidgets('a onebox containing code gets the native block', (
      tester,
    ) async {
      final aside = html.parse(blobOnebox).querySelector('aside.onebox')!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: OneboxCard(data: OneboxData.from(aside))),
        ),
      );
      await tester.pump();

      expect(find.byType(CodeBlock), findsOneWidget);
      expect(find.text('def self.get_from_url(url)'), findsOneWidget);
    });
  });
}

class _CountingLines extends ListBase<CodeLine> {
  _CountingLines(this.source);
  final List<CodeLine> source;
  int reads = 0;
  @override
  int get length => source.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  CodeLine operator [](int index) {
    reads++;
    return source[index];
  }

  @override
  void operator []=(int index, CodeLine value) =>
      throw UnsupportedError('read only');
}
