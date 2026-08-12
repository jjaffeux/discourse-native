import 'package:discourse_native/src/shell/oneboxes/discourse/category/block.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/topic/block.dart';
import 'package:discourse_native/src/shell/oneboxes/discourse/user/block.dart';
import 'package:discourse_native/src/shell/oneboxes/github/commit/block.dart';
import 'package:discourse_native/src/shell/oneboxes/github/issue/block.dart';
import 'package:discourse_native/src/shell/oneboxes/github/pr/block.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// Real cooked output from meta.discourse.org, trimmed of nothing that matters.
const String genericOnebox = '''
<aside class="onebox allowlistedgeneric" data-onebox-src="https://forum.adunanza.net">
  <header class="source">
      <img src="https://cdn.example.com/icon.png" class="site-icon" alt="" width="32" height="32">
      <a href="https://forum.adunanza.net" target="_blank" rel="noopener">AduForum</a>
  </header>
  <article class="onebox-body">
    <div class="aspect-image" style="--aspect-ratio:136/66;"><img src="https://cdn.example.com/thumb.png" class="thumbnail" alt="" width="136" height="66"></div>
<h3><a href="https://forum.adunanza.net" target="_blank" rel="noopener">AduForum</a></h3>
  <p>Il network P2P ad alte prestazioni</p>
  </article>
  <div class="onebox-metadata">
  </div>
  <div style="clear: both"></div>
</aside>
''';

const String twitterOnebox = '''
<aside class="onebox twitterstatus" data-onebox-src="https://twitter.com/codinghorror/status/1056641824733855744">
  <header class="source">
      <a href="https://twitter.com/codinghorror/status/1056641824733855744" target="_blank" rel="noopener">twitter.com</a>
  </header>
  <article class="onebox-body">
    <img src="https://cdn.example.com/avatar.jpeg" class="thumbnail onebox-avatar" alt="" width="48" height="48">
<h4><a href="https://twitter.com/codinghorror/status/1056641824733855744" target="_blank" rel="noopener">Jeff Atwood</a></h4>
<div class="twitter-screen-name"><a href="#" target="_blank" rel="noopener">@codinghorror</a></div>
<div class="tweet"><span class="tweet-description">250k followers?</span></div>
  </article>
</aside>
''';

dom.Element aside(String source) =>
    html.parse(source).querySelector('aside.onebox')!;

OneboxData parse(String source) => OneboxData.from(aside(source));

void main() {
  group('OneboxData', () {
    test('reads the envelope every engine shares', () {
      final data = parse(genericOnebox);

      expect(data.url, 'https://forum.adunanza.net');
      expect(data.siteName, 'AduForum');
      expect(data.siteIcon, 'https://cdn.example.com/icon.png');
      expect(data.title, 'AduForum');
      expect(data.titleUrl, 'https://forum.adunanza.net');
    });

    test('takes the thumbnail out of its aspect-image wrapper', () {
      final thumbnail = parse(genericOnebox).thumbnail!;

      expect(thumbnail.src, 'https://cdn.example.com/thumb.png');
      expect(thumbnail.aspectRatio, closeTo(136 / 66, 0.001));
      expect(thumbnail.isAvatar, isFalse);
    });

    test('bounds hostile thumbnail dimensions before layout', () {
      OneboxThumbnail thumbnail(String width, String height) {
        final image = html
            .parseFragment(
              '<img src="https://cdn.example.com/image.png" '
              'width="$width" height="$height">',
            )
            .querySelector('img')!;
        return OneboxThumbnail.from(image)!;
      }

      for (final dimensions in const [
        ('0', '1'),
        ('-1', '1'),
        ('1', '0'),
        ('1', '-1'),
        ('NaN', '1'),
        ('1', 'NaN'),
        ('Infinity', '1'),
        ('1', 'Infinity'),
      ]) {
        expect(
          thumbnail(dimensions.$1, dimensions.$2).aspectRatio,
          isNull,
          reason: '${dimensions.$1}x${dimensions.$2}',
        );
      }

      expect(thumbnail('1e308', '1e-308').aspectRatio, 4);
      expect(thumbnail('1e-308', '1e308').aspectRatio, 0.25);
      expect(thumbnail('16', '9').aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('leaves the body it did not claim for HtmlWidget', () {
      final data = parse(genericOnebox);

      // The title and the whole aspect-image wrapper are drawn natively, so
      // they must not be rendered a second time.
      expect(data.bodyHtml, contains('Il network P2P'));
      expect(data.bodyHtml, isNot(contains('aspect-image')));
      expect(data.bodyHtml, isNot(contains('<h3')));
    });

    test('recognises an engine that leads with an avatar', () {
      final data = parse(twitterOnebox);

      expect(data.siteName, 'twitter.com');
      expect(data.siteIcon, isNull);
      expect(data.title, 'Jeff Atwood');
      expect(data.thumbnail!.isAvatar, isTrue);
      // Everything the parser has no opinion about still reaches the reader.
      expect(data.bodyHtml, contains('@codinghorror'));
      expect(data.bodyHtml, contains('250k followers?'));
    });

    test('survives an engine with no header, title or image', () {
      final data = parse(
        '<aside class="onebox unknownengine" data-onebox-src="https://e.com">'
        '<article class="onebox-body"><p>Something new</p></article></aside>',
      );

      expect(data.url, 'https://e.com');
      expect(data.siteName, isNull);
      expect(data.title, isNull);
      expect(data.thumbnail, isNull);
      expect(data.bodyHtml, contains('Something new'));
    });
  });

  group('oneboxWidgetBuilder', () {
    test('claims oneboxes and nothing else', () {
      dom.Element element(String source) =>
          html.parse(source).querySelector('body')!.children.first;

      expect(
        oneboxWidgetBuilder(element('<aside class="onebox"></aside>')),
        isA<OneboxCard>(),
      );
      // Quotes are asides too, and are not ours.
      expect(
        oneboxWidgetBuilder(element('<aside class="quote"></aside>')),
        isNull,
      );
      expect(oneboxWidgetBuilder(element('<p>hello</p>')), isNull);
    });

    test('hands engines the asides they claim', () {
      Widget body(Widget widget) =>
          (widget as OneboxCard).child ?? const SizedBox();

      expect(
        body(oneboxWidgetBuilder(aside(prOnebox))!),
        isA<GithubPullRequestOnebox>(),
      );
      expect(
        body(oneboxWidgetBuilder(aside(issueOnebox))!),
        isA<GithubIssueOnebox>(),
      );
      expect(
        body(oneboxWidgetBuilder(aside(commitOnebox))!),
        isA<GithubCommitOnebox>(),
      );
      expect(
        body(oneboxWidgetBuilder(aside(discourseTopicOnebox))!),
        isA<DiscourseTopicOnebox>(),
      );
      expect(
        body(oneboxWidgetBuilder(aside(userOnebox))!),
        isA<DiscourseUserOnebox>(),
      );
      expect(
        body(oneboxWidgetBuilder(aside(categoryOnebox))!),
        isA<DiscourseCategoryOnebox>(),
      );
      // An engine nobody wrote yet still lands on its feet.
      expect(
        (oneboxWidgetBuilder(aside(genericOnebox))! as OneboxCard).child,
        isNull,
      );
    });
  });

  group('OneboxCard', () {
    testWidgets('draws the site, title and remaining body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: OneboxCard(data: parse(genericOnebox))),
        ),
      );
      await tester.pump();

      expect(find.text('AduForum'), findsNWidgets(2)); // header and title
      // The leftover body goes through HtmlWidget, which paints RichText.
      expect(
        find.textContaining('Il network P2P', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('bounds fixed-size network image decodes', (tester) async {
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: OneboxCard(data: parse(genericOnebox))),
        ),
      );

      final providers = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .whereType<ResizeImage>()
          .toList();
      expect(
        providers.map((provider) => provider.width),
        containsAll([40, 220]),
      );
      expect(
        providers.map((provider) => provider.allowUpscaling),
        everyElement(isFalse),
      );
    });

    testWidgets('generic destination is one named keyboard link', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = tester.binding.defaultBinaryMessenger;
      final launched = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const destination = 'https://example.com/article';
      const data = OneboxData(
        url: destination,
        siteIcon: null,
        siteName: 'Example',
        title: 'Example',
        titleUrl: destination,
        thumbnail: null,
        bodyHtml: '<p>Article description</p>',
      );
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(body: OneboxCard(data: data)),
          ),
        );
        await tester.pump();

        // Both visual labels remain, while the matching header and title are
        // announced only once as part of the composite link name.
        expect(find.text('Example'), findsNWidgets(2));
        final target = find.bySemanticsLabel(
          RegExp(r'Example.*Article description', dotAll: true),
        );
        expect(target, findsOneWidget);
        final node = tester.getSemantics(target);
        expect(_occurrences(node.label, 'Example'), 1);
        expect(
          node,
          isSemantics(
            isLink: true,
            isButton: false,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          tester.getSemantics(target),
          isSemantics(isFocusable: true, isFocused: true),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(launched, [destination]);
      } finally {
        semantics.dispose();
      }
    });
  });
}

int _occurrences(String source, String pattern) =>
    pattern.allMatches(source).length;

/// Minimal asides for the dispatch test; the full shapes live in each
/// engine's own test.
const String prOnebox = '''
<aside class="onebox githubpullrequest" data-onebox-src="https://github.com/discourse/discourse/pull/1">
  <article class="onebox-body">
    <div class="github-row">
      <div class="github-info-container">
        <h4><a href="https://github.com/discourse/discourse/pull/1">Title (#1)</a></h4>
      </div>
    </div>
  </article>
</aside>
''';

const String issueOnebox = '''
<aside class="onebox githubissue" data-onebox-src="https://github.com/discourse/discourse/issues/1">
  <article class="onebox-body">
    <div class="github-row">
      <div class="github-info-container">
        <h4><a href="https://github.com/discourse/discourse/issues/1">Title</a></h4>
      </div>
    </div>
  </article>
</aside>
''';

const String commitOnebox = '''
<aside class="onebox githubcommit" data-onebox-src="https://github.com/discourse/discourse/commit/abc1234">
  <article class="onebox-body">
    <div class="github-row">
      <div class="github-info-container">
        <h4><a href="https://github.com/discourse/discourse/commit/abc1234">Fix</a></h4>
      </div>
    </div>
  </article>
</aside>
''';

const String discourseTopicOnebox = '''
<aside class="onebox discoursetopic" data-onebox-src="https://meta.discourse.org/t/some-topic/123">
  <article class="onebox-body">
    <div class="title-wrapper">
      <h3><a href="https://meta.discourse.org/t/some-topic/123">Some topic</a></h3>
    </div>
  </article>
</aside>
''';

const String userOnebox = '''
<aside class="onebox" data-onebox-src="https://meta.discourse.org/u/octocat">
  <article class="onebox-body user-onebox">
    <h3><a href="https://meta.discourse.org/u/octocat">@octocat</a></h3>
  </article>
</aside>
''';

const String categoryOnebox = '''
<aside class="onebox category-onebox" data-onebox-src="https://meta.discourse.org/c/feature/60">
  <article class="onebox-body category-onebox-body">
    <h3><a class="badge-category__wrapper" href="https://meta.discourse.org/c/feature/60"><span class="badge-category__name">feature</span></a></h3>
  </article>
</aside>
''';
