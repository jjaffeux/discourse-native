import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

Future<void> pumpCooked(WidgetTester tester, String html) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(child: CookedHtml(html: html)),
      ),
    ),
  );
  await tester.pump();
}

bool isUnderlined(WidgetTester tester, String text) =>
    styleOf(tester, text).decoration?.contains(TextDecoration.underline) ??
    false;

/// The style HtmlWidget resolved for the run of text reading [text].
TextStyle styleOf(WidgetTester tester, String text) {
  final richText = tester
      .widgetList<RichText>(find.byType(RichText))
      .firstWhere((widget) => widget.text.toPlainText().contains(text));

  TextStyle? found;
  richText.text.visitChildren((span) {
    if (span is TextSpan && span.text?.contains(text) == true) {
      found = span.style;
      return false;
    }
    return true;
  });

  return found ?? richText.text.style!;
}

void main() {
  group('links', () {
    testWidgets('are not underlined, the way Discourse draws them', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<p>See <a href="https://meta.discourse.org">meta</a>.</p>',
      );

      expect(isUnderlined(tester, 'meta'), isFalse);
    });

    testWidgets('keep the decoration their own markup asks for', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<p><a href="https://meta.discourse.org"><del>gone</del></a></p>',
      );

      expect(styleOf(tester, 'gone').decoration, TextDecoration.lineThrough);
    });

    testWidgets('stay undecorated inside a quote', (tester) async {
      await pumpCooked(
        tester,
        '<blockquote><p><a href="https://meta.discourse.org">meta</a></p>'
        '</blockquote>',
      );

      expect(isUnderlined(tester, 'meta'), isFalse);
    });

    testWidgets('stay undecorated inside a onebox body', (tester) async {
      await pumpCooked(
        tester,
        '<aside class="onebox"><article class="onebox-body">'
        '<p>Read <a href="https://meta.discourse.org">meta</a></p>'
        '</article></aside>',
      );

      expect(isUnderlined(tester, 'meta'), isFalse);
    });
  });

  group('inline code', () {
    testWidgets('is drawn as a chip rather than bare monospace text', (
      tester,
    ) async {
      await pumpCooked(
        tester,
        '<p>Try <code>tl3_requires_posts_read</code>.</p>',
      );

      final code = tester.widget<InlineCode>(find.byType(InlineCode));
      expect(code.text, 'tl3_requires_posts_read');
      expect(code.isLink, isFalse);

      final style = tester
          .widget<Text>(
            find.descendant(
              of: find.byType(InlineCode),
              matching: find.byType(Text),
            ),
          )
          .style!;
      expect(style.fontFamilyFallback, contains('monospace'));
      // Smaller than the prose it sits in, the way `0.875rem` is.
      expect(style.fontSize, lessThan(14));
    });

    testWidgets('keeps the whitespace the author wrote', (tester) async {
      await pumpCooked(tester, '<p>Type <code>a  b</code>.</p>');

      expect(tester.widget<InlineCode>(find.byType(InlineCode)).text, 'a  b');
    });

    testWidgets('is colored as a link when it is one', (tester) async {
      await pumpCooked(
        tester,
        '<p><a href="https://meta.discourse.org"><code>meta</code></a></p>',
      );

      expect(tester.widget<InlineCode>(find.byType(InlineCode)).isLink, isTrue);
    });

    testWidgets('leaves a code block alone', (tester) async {
      await pumpCooked(
        tester,
        '<pre><code class="lang-ruby">puts 1</code></pre>',
      );

      expect(find.byType(InlineCode), findsNothing);
      expect(find.byType(CodeBlock), findsOneWidget);
    });
  });
}
