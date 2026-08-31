import 'dart:ui' as ui;

import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/shell/quote_panel.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

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
