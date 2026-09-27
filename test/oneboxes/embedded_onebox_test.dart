import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/oneboxes/embedded.dart';
import 'package:discourse_native/src/styleguide/examples/onebox_provider_samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:webview_all/webview_all.dart';

import '../support/fake_media_webview.dart';

void main() {
  test('all core iframe providers retain their embed URL', () {
    for (final url in oneboxProviderSamples.values) {
      final element = html
          .parseFragment('<iframe src="$url"></iframe>')
          .children
          .single;
      final data = EmbeddedOneboxData.from(element)!;
      expect(data.uri.host, Uri.parse(url).host);
      expect(data.externalUri, Uri.parse(url));
    }
  });

  test(
    'rejects executable documents, credentials and unrecognized scripts',
    () {
      for (final url in [
        'javascript:alert(1)',
        'data:text/html,hello',
        'file:///etc/passwd',
        'https://user:pass@example.com/embed',
      ]) {
        expect(
          EmbeddedOneboxData.from(
            html.parseFragment('<iframe src="$url"></iframe>').children.single,
          ),
          isNull,
        );
      }
      for (final url in [
        'https://asciinema.org.evil.test/a/123.js',
        'https://asciinema.org/other.js',
        'https://example.com/a/123.js',
      ]) {
        expect(
          EmbeddedOneboxData.from(
            html.parseFragment('<script src="$url"></script>').children.single,
          ),
          isNull,
        );
      }
    },
  );

  test('only a server onebox names the link an embed opens in the browser', () {
    const maps = 'https://www.google.com/maps/embed?pb=abc';
    EmbeddedOneboxData embed(String wrapper) => EmbeddedOneboxData.from(
      html
          .parseFragment(
            wrapper.replaceFirst('%', '<iframe src="$maps"></iframe>'),
          )
          .querySelector('iframe')!,
      siteUrl: 'https://forum.example',
    )!;

    // Authors may put data-* on their own divs and asides.
    for (final wrapper in [
      '<div data-onebox-src="https://evil.example/maps-login">%</div>',
      '<aside class="quote" data-onebox-src="https://evil.example/">%</aside>',
      '<div class="onebox" data-onebox-src="https://evil.example/">'
          '<p>%</p></div>',
    ]) {
      expect(embed(wrapper).externalUri, Uri.parse(maps), reason: wrapper);
    }

    expect(
      embed(
        '<div data-onebox-src="https://evil.example/">'
        '<aside class="onebox allowlistedgeneric" '
        'data-onebox-src="https://maps.example/place">'
        '<article class="onebox-body">%</article></aside></div>',
      ).externalUri,
      Uri.parse('https://maps.example/place'),
    );
  });

  test('normalizes protocol-relative URLs and finite dimensions', () {
    final element = html
        .parseFragment(
          '<iframe src="//player.vimeo.com/video/123" height="Infinity" width="0" style="height: 9999px"></iframe>',
        )
        .children
        .single;
    final data = EmbeddedOneboxData.from(element)!;
    expect(data.uri.scheme, 'https');
    expect(data.height, 400);
    expect(data.width, isNull);
    final styled = EmbeddedOneboxData.from(
      html
          .parseFragment(
            '<iframe src="https://www.tiktok.com/embed/v2/123" style="height: 560.5px;"></iframe>',
          )
          .children
          .single,
    )!;
    expect(styled.height, 560.5);
  });

  test('Twitch parent matches the actual native host document', () {
    final data = EmbeddedOneboxData.from(
      html
          .parseFragment(
            '<iframe src="https://player.twitch.tv/?video=123&amp;parent=forum.test"></iframe>',
          )
          .children
          .single,
    )!;
    expect(data.uri.queryParameters['parent'], 'player.twitch.tv');
    expect(data.uri.queryParameters['video'], '123');
    expect(data.uri.queryParameters['autoplay'], 'false');
  });

  test('Asciinema bootstrap translates only to its iframe', () {
    final data = EmbeddedOneboxData.from(
      html
          .parseFragment(
            '<script src="https://asciinema.org/a/8332.js"></script>',
          )
          .children
          .single,
    )!;
    expect(data.uri.toString(), 'https://asciinema.org/a/8332/iframe');
    expect(data.externalUri.toString(), 'https://asciinema.org/a/8332');
  });

  testWidgets('cooked iframe loads on demand and retires on removal', (
    tester,
  ) async {
    final previous = WebViewPlatform.instance;
    final platform = FakeMediaWebViewPlatform();
    WebViewPlatform.instance = platform;
    addTearDown(() {
      if (previous != null) WebViewPlatform.instance = previous;
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CookedHtml(
            buildAsync: false,
            html:
                '<iframe src="https://player.vimeo.com/video/76979871" srcdoc="unsafe" title="Vimeo"></iframe>',
          ),
        ),
      ),
    );
    expect(find.byType(EmbeddedOnebox), findsOneWidget);
    expect(platform.controllers, isEmpty);
    await tester.tap(find.text('Load embed'));
    await tester.pump();
    expect(find.byType(DEmbed), findsOneWidget);
    final controller = platform.controllers.single;
    expect(controller.documents.single.html, contains('player.vimeo.com'));
    expect(controller.documents.single.html, isNot(contains('unsafe')));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(controller.channels, isEmpty);
    expect(controller.documents.last.html, isNot(contains('player.vimeo.com')));
  });

  testWidgets('CookedHtml reaches Asciinema scripts', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CookedHtml(
            buildAsync: false,
            html: '<script src="https://asciinema.org/a/8332.js"></script>',
          ),
        ),
      ),
    );
    expect(find.byType(EmbeddedOnebox), findsOneWidget);
  });
}
