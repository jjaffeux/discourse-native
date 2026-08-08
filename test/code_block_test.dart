import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

/// Real cooked output from meta.discourse.org: a git blob onebox puts a
/// numbered `<ol>` inside the `<pre>`, which is what wrecked it under
/// HtmlWidget.
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

void main() {
  group('CodeBlockData', () {
    test('reads a git blob onebox as numbered lines', () {
      final lines = parseBlock(blobOnebox).lines;

      expect(lines.length, 4);
      expect(lines.first.text, 'def self.get_from_url(url)');
      expect(lines.first.number, 78);
      expect(lines.last.number, 81);
      // The blank line in the middle is a line, not something to collapse.
      expect(lines[2].text, isEmpty);
    });

    test('keeps indentation, which is the whole point of a code block', () {
      expect(parseBlock(blobOnebox).lines[1].text, '  return if url.blank?');
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
      // The same four lines, still numbered from 78, still selected.
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
  });

  group('CodeBlock', () {
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
      // And the scrollbar is there to say so.
      expect(
        tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
        isTrue,
      );
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
