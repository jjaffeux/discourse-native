import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

/// Real cooked output from meta.discourse.org.
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

/// A quote of another topic carries the topic title as a link instead.
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
    test('reads the attribution of a quoted post', () {
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

    test('drops the quote controls from the attribution', () {
      expect(parse(postQuote).title, isNot(contains('quote-controls')));
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
  });
}
