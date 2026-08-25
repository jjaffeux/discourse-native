import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/site_image.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

const _video = YoutubeVideoData(
  videoId: 'dQw4w9WgXcQ',
  listId: null,
  title: 'A useful video',
  thumbnailUrl: null,
  startSeconds: null,
  endSeconds: null,
  loop: false,
);

void main() {
  group('YoutubeVideoData', () {
    test('reads the lazy-video plugin markup', () {
      final element = html_parser
          .parseFragment('''
<div class="youtube-onebox lazy-video-container"
  data-video-id="dQw4w9WgXcQ"
  data-video-title="A &amp; B"
  data-video-start-time="1h2m3s"
  data-video-list-id="PL_test-1"
  data-provider-name="youtube">
  <a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ&amp;list=PL_test-1&amp;t=1h2m3s"
     class="video-thumbnail">
    <img class="youtube-thumbnail" src="https://cdn.example/thumbnail.jpg">
  </a>
</div>
''')
          .querySelector('div')!;

      final data = YoutubeVideoData.tryParse(element);

      expect(data, isNotNull);
      expect(data!.videoId, 'dQw4w9WgXcQ');
      expect(data.listId, 'PL_test-1');
      expect(data.title, 'A & B');
      expect(data.thumbnailUrl, 'https://cdn.example/thumbnail.jpg');
      expect(data.startSeconds, 3723);
      expect(
        data.watchUri,
        Uri.parse(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL_test-1&t=3723s',
        ),
      );
    });

    test('reads the core iframe and its preceding hidden thumbnail', () {
      final document = html_parser.parseFragment('''
<img class="youtube-thumbnail onebox" style="display:none"
  src="https://cdn.example/core.jpg" title="Core title">
<iframe class="youtube-onebox"
  src="https://www.youtube.com/embed/dQw4w9WgXcQ?list=PL_test&amp;start=42&amp;end=90&amp;loop=1">
</iframe>
''');

      final data = YoutubeVideoData.tryParse(document.querySelector('iframe')!);

      expect(data, isNotNull);
      expect(data!.videoId, 'dQw4w9WgXcQ');
      expect(data.listId, 'PL_test');
      expect(data.title, 'Core title');
      expect(data.thumbnailUrl, 'https://cdn.example/core.jpg');
      expect(data.startSeconds, 42);
      expect(data.endSeconds, 90);
      expect(data.loop, isTrue);
    });

    test('reads a playlist-only core iframe', () {
      final iframe = html_parser
          .parseFragment('''
<iframe class="youtube-onebox"
  src="https://www.youtube.com/embed/videoseries?list=PL_only"></iframe>
''')
          .querySelector('iframe')!;

      final data = YoutubeVideoData.tryParse(iframe);

      expect(data, isNotNull);
      expect(data!.videoId, isNull);
      expect(data.listId, 'PL_only');
      expect(data.title, 'YouTube playlist');
      expect(data.thumbnailUrl, isNull);
    });

    test('accepts watch, short, embed, live, and youtu.be URLs', () {
      final cases = <String, String>{
        'https://www.youtube.com/watch?v=watch_id': 'watch_id',
        'https://youtube.com/shorts/short_id': 'short_id',
        'https://m.youtube.com/embed/embed_id': 'embed_id',
        'https://www.youtube.com/live/live_id': 'live_id',
        'https://youtu.be/short-link': 'short-link',
      };

      for (final entry in cases.entries) {
        expect(
          YoutubeVideoData.tryParseUrl(entry.key)?.videoId,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('reads start times from query strings and fragments', () {
      expect(
        YoutubeVideoData.tryParseUrl(
          'https://youtu.be/video?t=2m14s',
        )?.startSeconds,
        134,
      );
      expect(
        YoutubeVideoData.tryParseUrl(
          'https://youtu.be/video#t=1h1m1s',
        )?.startSeconds,
        3661,
      );
    });

    test('rejects unrelated hosts, paths, credentials, and malformed ids', () {
      for (final value in [
        'https://youtube.com.example/watch?v=video',
        'https://user@youtube.com/watch?v=video',
        'https://youtube.com/@discourse',
        'https://youtube.com/watch?v=not%2Fa%2Fvideo',
        'javascript:alert(1)',
      ]) {
        expect(YoutubeVideoData.tryParseUrl(value), isNull, reason: value);
      }
    });

    test('declines malformed cooked containers', () {
      final wrongProvider = html_parser
          .parseFragment('''
<div class="youtube-onebox lazy-video-container"
  data-provider-name="vimeo" data-video-id="video"></div>
''')
          .querySelector('div')!;
      final badIframe = html_parser
          .parseFragment('''
<iframe class="youtube-onebox"
  src="https://example.com/embed/video"></iframe>
''')
          .querySelector('iframe')!;

      expect(YoutubeVideoData.tryParse(wrongProvider), isNull);
      expect(YoutubeVideoData.tryParse(badIframe), isNull);
    });
  });

  group('YouTube embed document', () {
    test('builds encoded playback parameters and forum origin', () {
      final origin = youtubeForumOrigin(
        'https://meta.discourse.org:443/t/a-topic/1?ignored=true#ignored',
      );
      const data = YoutubeVideoData(
        videoId: 'video_id',
        listId: 'PL_list',
        title: 'A "quoted" & risky <title>',
        thumbnailUrl: null,
        startSeconds: 12,
        endSeconds: 34,
        loop: true,
      );

      expect(origin, Uri.parse('https://meta.discourse.org'));
      final embed = youtubeEmbedUri(data, forumOrigin: origin);
      expect(embed.host, 'www.youtube.com');
      expect(embed.path, '/embed/video_id');
      expect(embed.queryParameters, {
        'autoplay': '1',
        'playsinline': '1',
        'rel': '0',
        'list': 'PL_list',
        'start': '12',
        'end': '34',
        'loop': '1',
        'playlist': 'video_id',
        'origin': 'https://meta.discourse.org',
      });

      final html = buildYoutubeEmbedHtml(data, forumOrigin: origin);
      expect(html, contains('referrerpolicy="origin"'));
      expect(html, contains('<meta name="referrer" content="origin">'));
      expect(html, contains('A &quot;quoted&quot; &amp; risky &lt;title&gt;'));
      expect(html, contains('autoplay=1&amp;playsinline=1&amp;rel=0'));
      expect(html, isNot(contains('A "quoted" & risky <title>')));
    });

    test('builds the playlist endpoint without a video id', () {
      const playlist = YoutubeVideoData(
        videoId: null,
        listId: 'PL_only',
        title: 'Playlist',
        thumbnailUrl: null,
        startSeconds: null,
        endSeconds: null,
        loop: false,
      );

      expect(youtubeEmbedUri(playlist).path, '/embed/videoseries');
      expect(youtubeEmbedUri(playlist).queryParameters['list'], 'PL_only');
    });

    test('only permits the initial local document as a main-frame load', () {
      final base = Uri.parse('https://meta.discourse.org');

      expect(isYoutubeDocumentNavigation('about:blank', base), isTrue);
      expect(
        isYoutubeDocumentNavigation('data:text/html,<html></html>', base),
        isTrue,
      );
      expect(
        isYoutubeDocumentNavigation('https://meta.discourse.org/', base),
        isTrue,
      );
      expect(
        isYoutubeDocumentNavigation('https://www.youtube.com/watch?v=x', base),
        isFalse,
      );
    });

    test('recognises only the exact initial iframe request', () {
      final origin = Uri.parse('https://meta.discourse.org');
      final expected = youtubeEmbedUri(_video, forumOrigin: origin);

      expect(
        isYoutubeInitialEmbedNavigation(
          expected.toString(),
          _video,
          forumOrigin: origin,
        ),
        isTrue,
      );
      expect(
        isYoutubeInitialEmbedNavigation(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          _video,
          forumOrigin: origin,
        ),
        isFalse,
      );
    });
  });

  group('YoutubeVideo', () {
    testWidgets('shows separate accessible play and external-link actions', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: YoutubeVideo(data: _video, siteUrl: null)),
        ),
      );

      expect(
        find.bySemanticsLabel('Play video: A useful video'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Open on YouTube: A useful video'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('creates the player only after activation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: YoutubeVideo(
                data: _video,
                siteUrl: 'https://meta.discourse.org/t/topic/1',
                playerBuilder: (data, origin) => ColoredBox(
                  key: const ValueKey('fake-youtube-player'),
                  color: Colors.black,
                  child: Text('${data.videoId} from $origin'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('fake-youtube-player')), findsNothing);

      await tester.tap(find.bySemanticsLabel('Play video: A useful video'));
      await tester.pump();

      final player = find.byKey(const ValueKey('fake-youtube-player'));
      expect(player, findsOneWidget);
      expect(
        find.text('dQw4w9WgXcQ from https://meta.discourse.org'),
        findsOneWidget,
      );
      expect(tester.getSize(player).height, 200);
    });

    testWidgets('keeps an activated player alive while it scrolls offscreen', (
      tester,
    ) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scroll,
              children: [
                YoutubeVideo(
                  data: _video,
                  siteUrl: 'https://meta.discourse.org',
                  playerBuilder: (_, _) => const ColoredBox(
                    key: ValueKey('kept-youtube-player'),
                    color: Colors.black,
                  ),
                ),
                for (var i = 0; i < 20; i++) const SizedBox(height: 200),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.bySemanticsLabel('Play video: A useful video'));
      await tester.pump();
      expect(find.byKey(const ValueKey('kept-youtube-player')), findsOneWidget);

      scroll.jumpTo(2000);
      await tester.pump();
      scroll.jumpTo(0);
      await tester.pump();

      expect(find.byKey(const ValueKey('kept-youtube-player')), findsOneWidget);
      expect(find.bySemanticsLabel('Play video: A useful video'), findsNothing);
    });
  });

  group('CookedHtml integration', () {
    const lazyMarkup = '''
<div class="youtube-onebox lazy-video-container"
  data-video-id="dQw4w9WgXcQ"
  data-video-title="Shared player"
  data-video-start-time=""
  data-video-list-id=""
  data-provider-name="youtube">
  <a href="https://www.youtube.com/watch?v=dQw4w9WgXcQ"
     class="video-thumbnail"></a>
</div>
''';

    testWidgets('uses the same full-width renderer in posts and chat', (
      tester,
    ) async {
      for (final compact in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                child: CookedHtml(
                  html: lazyMarkup,
                  siteUrl: 'https://meta.discourse.org',
                  compactParagraphs: compact,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(YoutubeVideo), findsOneWidget);
        expect(tester.getSize(find.byType(YoutubeVideo)).width, 600);
      }
    });

    testWidgets('claims the legacy core iframe fallback', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CookedHtml(
              siteUrl: 'https://meta.discourse.org',
              html: '''
<img class="youtube-thumbnail onebox" style="display:none"
  src="https://img.youtube.com/vi/dQw4w9WgXcQ/maxresdefault.jpg">
<iframe class="youtube-onebox"
  src="https://www.youtube.com/embed/dQw4w9WgXcQ?start=12"></iframe>
''',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(YoutubeVideo), findsOneWidget);
      // The hidden core image is suppressed; the one remaining image is the
      // native poster reusing that thumbnail.
      expect(find.byType(SiteImage), findsOneWidget);
    });
  });
}
