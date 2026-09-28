import 'dart:ui' as ui;

import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/shell/quote_panel.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/media_pipeline.dart';

const String postQuote = '''
<aside class="quote no-group" data-username="martin" data-post="14" data-topic="322551">
<div class="title">
<div class="quote-controls"></div>
<img loading="lazy" alt="" width="24" height="24" src="/user_avatar/meta.discourse.org/martin/48/1_2.png" class="avatar"> martin:</div>
<blockquote>
<p>I guess since we are combining New and Unread into the one list.</p>
</blockquote>
</aside>
''';

const String crossTopicQuote = '''
<aside class="quote group-staff" data-username="sam" data-post="1" data-topic="1234">
<div class="title">
<div class="quote-controls"></div>
<img alt="" width="24" height="24" src="https://cdn.example.com/sam.png" class="avatar">
<a href="https://meta.discourse.org/t/a-topic/1234/1">A topic</a>
</div>
<blockquote><p>Quoted across topics.</p></blockquote>
</aside>
''';

String sameSiteTopicLink(String categoryBadge, {String title = 'Some topic'}) =>
    '''
<aside class="quote" data-post="1" data-topic="341126">
<div class="title">
<div class="quote-controls"></div>
<img alt="" width="24" height="24" src="https://cdn.example.com/martin.png" class="avatar">
<div class="quote-title__text-content">
<a href="https://meta.discourse.org/t/some-topic/341126">$title</a> $categoryBadge
</div>
</div>
<blockquote><p>The first post of the topic, excerpted.</p></blockquote>
</aside>
''';

String crossTopicQuoteTitled(String title) =>
    '''
<aside class="quote no-group" data-username="sam" data-post="1" data-topic="1234">
<div class="title">
<div class="quote-controls"></div>
<img alt="" width="24" height="24" src="https://cdn.example.com/sam.png" class="avatar"><a href="https://meta.discourse.org/t/a-topic/1234/1">$title</a></div>
<blockquote><p>Quoted across topics.</p></blockquote>
</aside>
''';

// Core's `performEmojiUnescape` output for a title's `:tada:` or 🎉: the
// image names the emoji bare, without the shortcode's colons.
const String titleEmoji =
    '<img width="20" height="20" '
    "src='https://meta.discourse.org/images/emoji/twitter/tada.png?v=12' "
    "title='tada' alt='tada' class='emoji'>";

const String plainBlockquote =
    '<blockquote>\n<p>Just a markdown quote.</p>\n</blockquote>';

QuoteData parse(String source) {
  final document = html.parse(source);
  final element =
      document.querySelector('aside.quote') ??
      document.querySelector('blockquote')!;
  return QuoteData.from(element);
}

void main() {
  group('QuoteData', () {
    test('reads a quoted post attribution without its controls', () {
      final data = parse(postQuote);

      expect(data.username, 'martin');
      expect(data.title, 'martin');
      expect(
        data.avatarUrl,
        '/user_avatar/meta.discourse.org/martin/48/1_2.png',
      );
      expect(data.link, isNull);
      expect(data.bodyHtml, contains('combining New and Unread'));
    });

    test('reads a cross-topic quote as a link to its source', () {
      final data = parse(crossTopicQuote);

      expect(data.title, 'A topic');
      expect(data.link, 'https://meta.discourse.org/t/a-topic/1234/1');
      expect(data.avatarUrl, 'https://cdn.example.com/sam.png');
    });

    test('reads a same-site topic link as its title, not its category', () {
      const badges = {
        'current':
            '<a class="badge-category__wrapper" href="/c/general/4">'
            '<span data-category-id="4" class="badge-category --style-square">'
            '<span class="badge-category__name">General</span></span></a>',
        'legacy':
            '<a class="badge-wrapper bullet" href="/c/general/4">'
            '<span class="badge-category-bg" '
            'style="background-color: #0088CC;"></span>'
            '<span class="badge-category clear-badge">General</span></a>',
        'unwrapped':
            '<span data-category-id="4" class="badge-category">'
            '<span class="badge-category__name">General</span></span>',
      };

      for (final MapEntry(key: shape, value: badge) in badges.entries) {
        final data = parse(sameSiteTopicLink(badge));

        expect(data.title, 'Some topic', reason: shape);
        expect(
          data.link,
          'https://meta.discourse.org/t/some-topic/341126',
          reason: shape,
        );
        expect(
          data.avatarUrl,
          'https://cdn.example.com/martin.png',
          reason: shape,
        );
      }
    });

    test(
      'keeps a linked title\'s emoji as the shortcode it was cooked from',
      () {
        const shapes = {
          'emoji and text': (
            '$titleEmoji Release party',
            ':tada: Release party',
          ),
          'emoji only': (titleEmoji, ':tada:'),
          'toned': (
            "<img src='/images/emoji/twitter/wave/4.png?v=12' "
                "title='wave:t4' alt='wave:t4' class='emoji'> Hello",
            ':wave:t4: Hello',
          ),
          'titled only': (
            "<img src='/images/emoji/twitter/tada.png?v=12' title='tada' "
                "class='emoji'> Release party",
            ':tada: Release party',
          ),
          'colon-wrapped alt': (
            "<img src='/images/emoji/twitter/tada.png?v=12' title=':tada:' "
                "alt=':tada:' class='emoji'> Release party",
            ':tada: Release party',
          ),
        };

        for (final MapEntry(key: shape, value: (markup, expected))
            in shapes.entries) {
          expect(
            parse(sameSiteTopicLink('', title: markup)).title,
            expected,
            reason: 'topic link, $shape',
          );
          expect(
            parse(crossTopicQuoteTitled(markup)).title,
            expected,
            reason: 'cross-topic quote, $shape',
          );
        }
      },
    );

    test('keeps a linked title\'s own trailing colon', () {
      expect(
        parse(sameSiteTopicLink('', title: 'Help needed:')).title,
        'Help needed:',
      );
      expect(
        parse(crossTopicQuoteTitled('Help needed:')).title,
        'Help needed:',
      );
      expect(parse(postQuote).title, 'martin');
    });

    test('reads a bare markdown blockquote as a quote with no attribution', () {
      final data = parse(plainBlockquote);

      expect(data.username, isNull);
      expect(data.title, isNull);
      expect(data.avatarUrl, isNull);
      expect(data.bodyHtml, contains('Just a markdown quote.'));
    });
  });

  group('quoteWidgetBuilder', () {
    test('claims quotes and leaves everything else alone', () {
      dom(String source) => html.parse(source).body!.children.first;

      expect(quoteWidgetBuilder(dom(postQuote)), isA<QuoteBlock>());
      expect(quoteWidgetBuilder(dom(plainBlockquote)), isA<QuoteBlock>());
      expect(
        quoteWidgetBuilder(dom('<aside class="onebox"><p>x</p></aside>')),
        isNull,
      );
      expect(quoteWidgetBuilder(dom('<p>plain</p>')), isNull);
    });
  });

  group('QuoteBlock', () {
    testWidgets('draws the attribution and the body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: QuoteBlock(data: parse(postQuote)),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('martin'), findsOneWidget);
      expect(
        find.textContaining('combining New and Unread', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('draws a linked title\'s emoji with the site artwork', (
      tester,
    ) async {
      installTestMediaPipeline(
        client: MockClient((_) async => http.Response('', 404)),
      );
      final controller = ShellController(
        instanceStore: FakeInstanceStore([instance('meta.example')]),
        api: FakeDiscourseApi(
          emojisBySite: {
            'https://meta.example': const [
              SiteEmoji(name: 'tada', url: '/images/emoji/twitter/tada.png'),
            ],
          },
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: QuoteBlock(
                    data: parse(
                      sameSiteTopicLink('', title: '$titleEmoji Release party'),
                    ),
                    siteUrl: 'https://meta.example',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage)).name,
          'tada',
        );
        expect(find.bySemanticsLabel(':tada: Release party'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('source attribution is a named keyboard link', (tester) async {
      const sourceUrl = 'https://meta.discourse.org/t/a-topic/1234/1';
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final launched = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: const Scaffold(
              body: QuoteBlock(
                data: QuoteData(
                  username: 'sam',
                  avatarUrl: null,
                  title: 'A topic',
                  link: sourceUrl,
                  bodyHtml: '<p>Quoted across topics.</p>',
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final target = find.bySemanticsLabel('A topic');
        expect(target, findsOneWidget);
        expect(tester.getSize(target).height, lessThan(44));
        expect(
          tester.getSemantics(target),
          isSemantics(
            label: 'A topic',
            isLink: true,
            isButton: false,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );
        final ink = find.descendant(of: target, matching: find.byType(InkWell));
        expect(ink, findsOneWidget);
        expect(
          tester.widget<InkWell>(ink).mouseCursor,
          SystemMouseCursors.click,
        );
        expect(tester.widget<InkWell>(ink).hoverColor, Colors.transparent);
        expect(
          tester.widget<InkWell>(ink).focusColor,
          Theme.of(tester.element(target)).shell.hover,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(launched, [sourceUrl]);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('keeps the accent out of the rounded right corners', (
      tester,
    ) async {
      const boundaryKey = ValueKey('quote-pixels');
      final dark = AppTheme.dark;

      await tester.pumpWidget(
        MaterialApp(
          theme: dark.copyWith(
            colorScheme: dark.colorScheme.copyWith(primary: Colors.red),
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 120,
                  child: QuoteBlock(data: parse(plainBlockquote)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final panel = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(QuotePanel),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((panel.decoration! as BoxDecoration).border, isNull);
      expect(
        find.descendant(
          of: find.byType(QuotePanel),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Positioned &&
                widget.left == 0 &&
                widget.top == 0 &&
                widget.bottom == 0 &&
                widget.width == 3,
          ),
        ),
        findsOneWidget,
      );

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final capture = (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return (width: image.width, height: image.height, bytes: bytes!);
        } finally {
          image.dispose();
        }
      }))!;

      var hasAccentFringe = false;
      for (var y = 0; y < capture.height; y += 1) {
        for (var x = capture.width - 16; x < capture.width; x += 1) {
          final offset = (y * capture.width + x) * 4;
          final red = capture.bytes.getUint8(offset);
          final green = capture.bytes.getUint8(offset + 1);
          final blue = capture.bytes.getUint8(offset + 2);
          if (red > green + 10 && red > blue + 10) {
            hasAccentFringe = true;
          }
        }
      }

      expect(hasAccentFringe, isFalse);
    });
  });
}
