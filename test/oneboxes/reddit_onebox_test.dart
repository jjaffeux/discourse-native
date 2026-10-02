import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/onebox.dart';
import 'package:discourse_native/src/shell/oneboxes/reddit.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:webview_all/webview_all.dart';

import '../support/fake_media_webview.dart';

// Markup emitted by Discourse's RedditMediaOnebox.
const redditPostOnebox = '''
<iframe class="reddit-onebox"
  src="https://embed.reddit.com/r/colors/comments/b4d5xm/literally_nothing_black_edition/?embed=true&amp;ref_source=embed&amp;ref=share"
  width="640" height="500" allowfullscreen></iframe>
''';

const redditCommentOnebox = '''
<iframe class="reddit-onebox"
  src="https://embed.reddit.com/r/cats/comments/abc123/my_cat_doing_a_backflip/def456/?embed=true&amp;ref_source=embed&amp;ref=share&amp;showmedia=false&amp;showmore=false&amp;depth=1&amp;context=1"
  width="640" height="300" allowfullscreen></iframe>
''';

RedditOneboxData? parse(String source) =>
    RedditOneboxData.from(html.parseFragment(source).children.first);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads the current post and comment iframe contracts', () {
    final post = parse(redditPostOnebox)!;
    expect(post.title, 'Reddit post · r/colors');
    expect(post.height, 500);
    expect(post.embedUri.queryParameters['embed'], 'true');
    expect(
      post.linkUri.toString(),
      'https://www.reddit.com/r/colors/comments/b4d5xm/literally_nothing_black_edition/',
    );
    final comment = parse(redditCommentOnebox)!;
    expect(comment.title, 'Reddit comment · r/cats');
    expect(comment.height, 300);
    expect(comment.embedUri.queryParameters['showmedia'], 'false');
    expect(comment.embedUri.queryParameters['context'], '1');
    expect(comment.linkUri.path, comment.embedUri.path);
    expect(comment.linkUri.hasQuery, isFalse);
  });

  test('supports redirected, legacy and protocol-relative embed hosts', () {
    for (final host in [
      'https://sh.reddit.com',
      'https://www.redditmedia.com',
      '//embed.reddit.com',
    ]) {
      final data = parse(
        redditPostOnebox.replaceFirst('https://embed.reddit.com', host),
      )!;
      expect(data.embedUri.scheme, 'https');
      expect(data.linkUri.host, 'www.reddit.com');
    }
  });

  test('matches the app theme while preserving comment context', () {
    final data = parse(redditCommentOnebox)!;
    final dark = data.embedUriFor(Brightness.dark);
    expect(dark.queryParameters['theme'], 'dark');
    expect(dark.queryParameters['context'], '1');
    expect(dark.queryParameters['showmedia'], 'false');
    expect(dark.path, data.embedUri.path);
    final light = parse(
      redditCommentOnebox.replaceFirst(
        'embed=true',
        'embed=true&amp;theme=dark',
      ),
    )!.embedUriFor(Brightness.light);
    expect(light.queryParameters, isNot(contains('theme')));
    expect(light.queryParameters['context'], '1');
  });

  test('allows canonical title slugs for the same post or comment only', () {
    final post = parse(redditPostOnebox)!;
    expect(
      post.allowsNavigation(
        Uri.parse('https://sh.reddit.com/r/colors/comments/b4d5xm/new_title/'),
      ),
      isTrue,
    );
    expect(
      post.allowsNavigation(
        Uri.parse('https://sh.reddit.com/r/colors/comments/b4d5xm/'),
      ),
      isTrue,
    );
    expect(
      post.allowsNavigation(
        Uri.parse('https://sh.reddit.com/r/colors/comments/other/post/'),
      ),
      isFalse,
    );
    final comment = parse(redditCommentOnebox)!;
    expect(
      comment.allowsNavigation(
        Uri.parse(
          'https://sh.reddit.com/r/cats/comments/abc123/new_title/def456/',
        ),
      ),
      isTrue,
    );
    expect(
      comment.allowsNavigation(
        Uri.parse(
          'https://sh.reddit.com/r/cats/comments/abc123/new_title/other/',
        ),
      ),
      isFalse,
    );
  });

  test('preserves user posts, comment paths and escaped title slugs', () {
    final data = parse(
      redditCommentOnebox.replaceFirst(
        '/r/cats/comments/abc123/my_cat_doing_a_backflip/',
        '/user/example/comments/abc123/caf%C3%A9/',
      ),
    )!;
    expect(data.title, 'Reddit comment · user/example');
    expect(
      data.linkUri.path,
      '/user/example/comments/abc123/caf%C3%A9/def456/',
    );
  });

  test('declines unrelated and malformed markup without mutating the DOM', () {
    final element = html.parseFragment(redditPostOnebox).children.single;
    final original = element.outerHtml;
    expect(oneboxWidgetBuilder(element), isNotNull);
    expect(element.outerHtml, original);
    for (final source in [
      '<p>Reddit</p>',
      '<iframe src="https://embed.reddit.com/r/cats/comments/abc123/"></iframe>',
      '<iframe class="reddit-onebox"></iframe>',
      for (final url in [
        '',
        'javascript:alert(1)',
        'file:///tmp/post',
        'http://embed.reddit.com/r/cats/comments/abc123/',
        'https:///r/cats/comments/abc123/',
        'https://embed.reddit.com.evil.example/r/cats/comments/abc123/',
        'https://user@embed.reddit.com/r/cats/comments/abc123/',
        'https://embed.reddit.com:8443/r/cats/comments/abc123/',
        'https://embed.reddit.com/login',
        'https://embed.reddit.com/r/cats/comments/',
        'https://embed.reddit.com/r/cats/comments/not-an-id/',
        'https://embed.reddit.com/r/cats/comments/abc123/title/invalid-id/',
        'https://embed.reddit.com/r/cats/comments/abc123/title/comment/extra/',
        'https://embed.reddit.com/r/%FF/comments/abc123/',
        'https://embed.reddit.com/r/cats/comments/abc123/a%2Fb/',
      ])
        '<iframe class="reddit-onebox" src="$url"></iframe>',
    ]) {
      expect(
        redditOneboxWidgetBuilder(html.parseFragment(source).children.first),
        isNull,
        reason: source,
      );
    }
  });

  test('bounds remote heights and falls back to post or comment defaults', () {
    for (final value in ['-1', '0', 'NaN', 'Infinity', 'bad']) {
      expect(
        parse(
          redditPostOnebox.replaceFirst('height="500"', 'height="$value"'),
        )!.height,
        500,
      );
      expect(
        parse(
          redditCommentOnebox.replaceFirst('height="300"', 'height="$value"'),
        )!.height,
        300,
      );
    }
    expect(
      parse(
        redditPostOnebox.replaceFirst('height="500"', 'height="1"'),
      )!.height,
      120,
    );
    expect(
      parse(
        redditPostOnebox.replaceFirst('height="500"', 'height="1e9"'),
      )!.height,
      2000,
    );
  });

  group('cooked Reddit oneboxes', () {
    late FakeMediaWebViewPlatform platform;
    late WebViewPlatform previous;
    late List<String> launched;
    const launcher = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() {
      previous = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
      platform = FakeMediaWebViewPlatform();
      WebViewPlatform.instance = platform;
      launched = [];
      messenger.setMockMethodCallHandler(launcher, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
    });
    tearDown(() {
      WebViewPlatform.instance = previous;
      messenger.setMockMethodCallHandler(launcher, null);
    });

    testWidgets('malformed query bytes do not break cooked Reddit rendering', (
      tester,
    ) async {
      final markup = redditCommentOnebox.replaceFirst(
        'embed=true',
        'bad=%FF&amp;%FF=bad&amp;embed=true&amp;ref=second',
      );
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: CookedHtml(buildAsync: false, html: markup)),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final embed = tester.widget<DEmbed>(find.byType(DEmbed));
        expect(embed.uri.queryParameters['embed'], 'true');
        expect(embed.uri.queryParameters['context'], '1');
        expect(embed.uri.queryParametersAll['ref'], ['second', 'share']);
        expect(embed.uri.queryParameters, isNot(contains('bad')));
        expect(
          embed.uri.queryParameters['theme'],
          theme.brightness == Brightness.dark ? 'dark' : null,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });

    for (final (markup, height) in [
      (redditPostOnebox, 500.0),
      (redditCommentOnebox, 300.0),
    ]) {
      testWidgets(
        'renders a $height-pixel Reddit embed without a footer or bottom gap',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SingleChildScrollView(child: CookedHtml(html: markup)),
              ),
            ),
          );
          await tester.pump();
          final controller = platform.controllers.single;
          expect(
            controller.documents.single.html,
            contains('embed.reddit.com'),
          );
          expect(controller.documents.single.html, contains('resize.embed'));
          expect(find.byType(DEmbed), findsOneWidget);
          expect(tester.getSize(find.byType(WebViewWidget)), Size(640, height));
          controller.channels['NativeEmbed']!.onMessageReceived(
            const JavaScriptMessage(message: 'loaded'),
          );
          await tester.pumpAndSettle();
          expect(find.text('Open on Reddit'), findsNothing);
          expect(find.byType(DCard), findsNothing);
          expect(
            tester.getBottomLeft(find.byType(WebViewWidget)),
            tester.getBottomLeft(find.byType(DEmbed)),
          );
          final link = parse(markup)!.linkUri.toString();
          expect(
            await controller.delegate!.navigate(link, isMainFrame: false),
            NavigationDecision.prevent,
          );
          await tester.pumpAndSettle();
          expect(launched, [link]);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('fits narrow posts with large text in both themes', (
      tester,
    ) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 280,
                    child: MediaQuery(
                      data: MediaQueryData(textScaler: TextScaler.linear(2)),
                      child: CookedHtml(html: redditCommentOnebox),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.getSize(find.byType(WebViewWidget)).width, 280);
        expect(
          tester
              .widget<DEmbed>(find.byType(DEmbed))
              .uri
              .queryParameters['theme'],
          theme.brightness == Brightness.dark ? 'dark' : isNull,
        );
        platform.controllers.last.channels['NativeEmbed']!.onMessageReceived(
          const JavaScriptMessage(message: 'loaded'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Reddit comment · r/cats'), findsNothing);
        expect(find.byType(DCard), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
