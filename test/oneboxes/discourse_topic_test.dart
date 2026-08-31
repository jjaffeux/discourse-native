import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/topic/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/quote.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

const String discourseTopicOnebox = '''
<aside class="onebox discoursetopic" data-onebox-src="https://meta.discourse.org/t/some-interesting-topic/123">
  <header class="source">
    <img src="https://cdn.example.com/favicon.png" class="site-icon" width="16" height="16">
    <a href="https://meta.discourse.org/t/some-interesting-topic/123" target="_blank" rel="noopener">Meta Discourse &ndash; 7 Aug 26</a>
  </header>
  <article class="onebox-body">
    <img src="https://cdn.example.com/thumb.png" class="thumbnail" width="200" height="100">
    <div class="title-wrapper">
      <h3><a href="https://meta.discourse.org/t/some-interesting-topic/123" target="_blank" rel="noopener">Some interesting topic</a></h3>
      <div class="topic-category">
        <span class="badge-wrapper bullet">
          <span class="badge-category-bg" style="background-color: #0088CC;"></span>
          <span class="badge-category clear-badge">
            <span class="category-name">feature</span>
          </span>
        </span>
        <div class="topic-header-extra">
          <div class="list-tags">
            <div class="discourse-tags">
              <svg class="fa d-icon d-icon-tag svg-icon svg-string" xmlns="http://www.w3.org/2000/svg"><use href="#tag"></use></svg>
              <span class="discourse-tag simple">onebox</span>
              <span class="discourse-tag simple">native</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    <p>This is the excerpt of the topic as advertised by the site.</p>
  </article>
  <div class="onebox-metadata"></div>
  <div style="clear: both"></div>
</aside>
''';

const String localTopicOnebox = '''
<aside class="quote" data-post="1" data-topic="341126">
  <div class="title">
    <div class="quote-controls"></div>
    <img alt="" loading="lazy" src="/user_avatar/meta.discourse.org/martin/48/1.png" class="avatar">
    <div class="quote-title__text-content">
      <a href="https://meta.discourse.org/t/some-topic/341126">Some topic</a>
      <span class="badge-wrapper bullet"><span class="badge-category-bg" style="background-color: #0088CC;"></span></span>
    </div>
  </div>
  <blockquote>
    <p>The first post of the topic, excerpted.</p>
  </blockquote>
</aside>
''';

void main() {
  test('deep topic markup parses without recursive DOM traversal', () {
    const depth = 1000;
    final nested =
        '${List.filled(depth, '<div>').join()}'
        '<span class="category-name">Deep category</span>'
        '${List.filled(depth, '</div>').join()}';

    final aside = html
        .parse(
          '<aside class="onebox discoursetopic">'
          '<article class="onebox-body"><span class="badge-wrapper">'
          '$nested</span></article></aside>',
        )
        .querySelector('aside.onebox')!;
    final parsed = DiscourseTopicData.from(aside, OneboxData.from(aside));

    expect(parsed.categories.single.name, 'Deep category');
  });

  group('DiscourseTopicData', () {
    DiscourseTopicData parse(String source) {
      final aside = html.parse(source).querySelector('aside.onebox')!;
      return DiscourseTopicData.from(aside, OneboxData.from(aside));
    }

    test('reads category, tags and the excerpt', () {
      final data = parse(discourseTopicOnebox);

      expect(data.title, 'Some interesting topic');
      expect(data.categories, hasLength(1));
      expect(data.categories.single.name, 'feature');
      expect(data.categories.single.color, const Color(0xFF0088CC));
      expect(data.tags, ['onebox', 'native']);
      expect(
        data.description,
        'This is the excerpt of the topic as advertised by the site.',
      );
      expect(data.thumbnail?.src, 'https://cdn.example.com/thumb.png');
    });
  });

  group('DiscourseTopicOnebox', () {
    testWidgets('draws title, category, tags and excerpt', (tester) async {
      final aside = html
          .parse(discourseTopicOnebox)
          .querySelector('aside.onebox')!;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(child: oneboxWidgetBuilder(aside)!),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Some interesting topic'), findsOneWidget);
      expect(find.text('feature'), findsOneWidget);
      expect(find.text('onebox, native'), findsOneWidget);
      expect(
        find.text(
          'This is the excerpt of the topic as advertised by the site.',
        ),
        findsOneWidget,
      );
    });
  });

  group('a same-site topic link', () {
    testWidgets('arrives as a quote and renders as one', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: CookedHtml(html: localTopicOnebox),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(QuoteBlock), findsOneWidget);
      expect(find.text('Some topic'), findsOneWidget);
      expect(
        find.textContaining('The first post of the topic', findRichText: true),
        findsOneWidget,
      );
    });
  });
}
