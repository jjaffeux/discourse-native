import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/shell/code_block.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/inline_code.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';

import 'support/fakes.dart';

/// Cooked HTML on its own, with no shell above it — which is how a quote or an
/// onebox body can also be rendered, and is the case [CookedHtml] uses
/// `ShellScope.maybeOf` for.
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

/// The same, under a shell holding one connected site — which is what a post
/// in a topic is rendered in, and what an emoji needs to resolve its `src`.
Future<ShellController> pumpCookedInShell(
  WidgetTester tester,
  String html, {
  http.Client? emoji,
}) async {
  EmojiCache.instance = EmojiCache(
    client: emoji ?? MockClient((_) async => http.Response('', 404)),
  );
  addTearDown(EmojiCache.instance.clear);

  final controller = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();

  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(child: CookedHtml(html: html)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

/// A real 1×1 transparent PNG. It has to decode, not merely look like one:
/// [Image.memory] falls back to the shortcode when it cannot, which is the very
/// thing the emoji tests are distinguishing.
final Uint8List onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
  'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

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

  group('emoji', () {
    // What Discourse actually cooks: a root-relative src, the shortcode in both
    // `alt` and `title`, and a fixed 20px.
    const smile =
        '<p>Hello '
        '<img src="/images/emoji/twitter/slight_smile.png?v=15" '
        'title=":slight_smile:" class="emoji" alt=":slight_smile:" '
        'loading="lazy" width="20" height="20">'
        '</p>';

    testWidgets('are drawn from the site rather than left as a shortcode', (
      tester,
    ) async {
      await pumpCookedInShell(
        tester,
        smile,
        emoji: MockClient((_) async => http.Response.bytes(onePixelPng, 200)),
      );

      final image = tester.widget<EmojiImage>(find.byType(EmojiImage));
      expect(
        image.url,
        'https://meta.discourse.org/images/emoji/twitter/slight_smile.png?v=15',
      );
      // Before this existed, HtmlWidget could not resolve the src and rendered
      // the alt attribute — so the whole feature is that this is gone.
      expect(renderedText(':slight_smile:'), findsNothing);
    });

    testWidgets(
      'fall back to their shortcode when the site will not serve one',
      (tester) async {
        await pumpCookedInShell(tester, smile);

        expect(renderedText(':slight_smile:'), findsOneWidget);
      },
    );

    testWidgets('are left alone with no shell to resolve the site', (
      tester,
    ) async {
      // A quote or an onebox body rendered on its own. The alt text stands,
      // exactly as it did everywhere before emoji rendered at all.
      await pumpCooked(tester, smile);

      expect(find.byType(EmojiImage), findsNothing);
      expect(renderedText(':slight_smile:'), findsOneWidget);
    });

    testWidgets('leave an ordinary image alone', (tester) async {
      await pumpCookedInShell(
        tester,
        '<p><img src="/uploads/default/1.png" alt="a screenshot"></p>',
      );

      expect(find.byType(EmojiImage), findsNothing);
    });
  });
}

/// HtmlWidget renders into a bare RichText, which find.text ignores.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  description: 'rendered text containing "$text"',
);
