import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:video_player/video_player.dart';

void main() {
  group('InlineVideoData', () {
    test('reads the current lazy Discourse placeholder', () {
      final element = html_parser
          .parseFragment('''
        <div class="video-placeholder-container"
          data-video-src="/secure-uploads/original/demo.mp4"
          data-thumbnail-src="//cdn.example.com/demo.jpg"
          data-video-title="Demo clip"
          data-video-width="1920"
          data-video-height="1080"></div>
      ''')
          .children
          .single;

      final data = InlineVideoData.tryParse(
        element,
        siteUrl: 'https://meta.discourse.org',
      );

      expect(
        data?.source,
        Uri.parse(
          'https://meta.discourse.org/secure-uploads/original/demo.mp4',
        ),
      );
      expect(data?.posterUrl, 'https://cdn.example.com/demo.jpg');
      expect(data?.title, 'Demo clip');
      expect(data?.aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('reads activated oneboxes and nested source elements', () {
      final element = html_parser
          .parseFragment('''
        <div class="onebox video-onebox">
          <video poster="/uploads/poster.jpg" width="640" height="480">
            <source src="/uploads/demo.webm" type="video/webm">
            <a href="/uploads/demo.webm">Product tour</a>
          </video>
        </div>
      ''')
          .children
          .single;

      final data = InlineVideoData.tryParse(
        element,
        siteUrl: 'https://meta.discourse.org',
      );

      expect(
        data?.source,
        Uri.parse('https://meta.discourse.org/uploads/demo.webm'),
      );
      expect(data?.posterUrl, 'https://meta.discourse.org/uploads/poster.jpg');
      expect(data?.title, 'Product tour');
      expect(data?.aspectRatio, closeTo(4 / 3, 0.001));
    });

    test('reads a direct video src and derives its title', () {
      final element = html_parser
          .parseFragment(
            '<video src="https://cdn.example.com/a%20clip.mp4"></video>',
          )
          .children
          .single;

      final data = InlineVideoData.tryParse(element);

      expect(data?.source.host, 'cdn.example.com');
      expect(data?.title, 'a clip.mp4');
      expect(data?.aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('rejects missing, unsafe, unresolved, and unavailable sources', () {
      for (final markup in [
        '<video></video>',
        '<video src="javascript:alert(1)"></video>',
        '<video src="/relative.mp4"></video>',
        '<video src="https://meta.discourse.org/404"></video>',
      ]) {
        final element = html_parser.parseFragment(markup).children.single;
        expect(InlineVideoData.tryParse(element), isNull, reason: markup);
      }
    });
  });

  testWidgets('cooked topic placeholder becomes an inline video', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: CookedHtml(
            siteUrl: 'https://meta.discourse.org',
            html: '''
              <p>Before</p>
              <div class="video-placeholder-container"
                data-video-src="/uploads/demo.mp4"
                data-video-title="Demo"></div>
              <p>After</p>
            ''',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(InlineVideo), findsOneWidget);
    expect(find.bySemanticsLabel('Play video: Demo'), findsOneWidget);
  });

  testWidgets('cooked activated onebox becomes one inline video', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: CookedHtml(
            siteUrl: 'https://meta.discourse.org',
            html: '''
              <div class="onebox video-onebox">
                <video title="Demo"><source src="/uploads/demo.mp4"></video>
              </div>
            ''',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(InlineVideo), findsOneWidget);
  });

  testWidgets('player is constructed lazily and reset for a new source', (
    tester,
  ) async {
    var builds = 0;
    final first = InlineVideoData.fromUpload(
      url: '/uploads/first.mp4',
      title: 'First',
      siteUrl: 'https://meta.discourse.org',
    )!;
    final second = InlineVideoData.fromUpload(
      url: '/uploads/second.mp4',
      title: 'Second',
      siteUrl: 'https://meta.discourse.org',
    )!;

    Widget app(InlineVideoData data) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: InlineVideo(
          key: const ValueKey('video'),
          data: data,
          siteUrl: 'https://meta.discourse.org',
          playerBuilder: (context, data) {
            builds++;
            return ColoredBox(key: ValueKey(data.source), color: Colors.black);
          },
        ),
      ),
    );

    await tester.pumpWidget(app(first));
    expect(builds, 0);

    await tester.tap(find.bySemanticsLabel('Play video: First'));
    await tester.pump();
    expect(builds, 1);
    expect(find.byKey(ValueKey(first.source)), findsOneWidget);

    await tester.pumpWidget(app(second));
    await tester.pump();
    expect(builds, 1);
    expect(find.bySemanticsLabel('Play video: Second'), findsOneWidget);
    expect(find.byKey(ValueKey(first.source)), findsNothing);
  });

  testWidgets('an activated player is released with its offscreen list item', (
    tester,
  ) async {
    var disposals = 0;
    final data = InlineVideoData.fromUpload(
      url: '/uploads/demo.mp4',
      title: 'Demo',
      siteUrl: 'https://meta.discourse.org',
    )!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              children: [
                InlineVideo(
                  data: data,
                  siteUrl: 'https://meta.discourse.org',
                  maximumHeight: 180,
                  playerBuilder: (_, _) =>
                      _DisposeSpy(onDispose: () => disposals++),
                ),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Play video: Demo'));
    await tester.pump();
    expect(find.byType(_DisposeSpy), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();

    expect(find.byType(_DisposeSpy), findsNothing);
    expect(disposals, 1);
  });

  testWidgets('native controls keep playback active in a full-screen route', (
    tester,
  ) async {
    final data = InlineVideoData.fromUpload(
      url: '/uploads/demo.mp4',
      title: 'Demo',
      siteUrl: 'https://meta.discourse.org',
    )!;
    final controller = _FakeVideoPlayerController();
    var controllerBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: InlineVideoNativeSurface(
            data: data,
            siteUrl: null,
            credentials: null,
            lifecycle: null,
            controllerBuilder: (_) {
              controllerBuilds++;
              return controller;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const fullscreenButton = ValueKey('inline-video-fullscreen');
    expect(controllerBuilds, 1);
    expect(controller.value.isPlaying, isTrue);
    expect(
      tester.widget<IconButton>(find.byKey(fullscreenButton)).tooltip,
      'Enter full screen',
    );

    await tester.tap(find.byKey(fullscreenButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-video-fullscreen-view')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('Full-screen video player: Demo')),
      findsOneWidget,
    );
    expect(controllerBuilds, 1);
    expect(controller.value.isPlaying, isTrue);
    expect(find.byType(VideoPlayer), findsOneWidget);

    const closeButton = ValueKey('inline-video-fullscreen-close');
    expect(
      tester.widget<IconButton>(find.byKey(closeButton)).tooltip,
      'Exit full screen',
    );
    await tester.tap(find.byKey(closeButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-video-fullscreen-view')),
      findsNothing,
    );
    expect(find.byKey(fullscreenButton), findsOneWidget);
    expect(controllerBuilds, 1);
    expect(controller.value.isPlaying, isTrue);
  });

  test('Linux document escapes attributes and locks down remote content', () {
    final html = buildInlineVideoHtml(
      Uri.parse('https://cdn.example.com/video.mp4?a=%22%3E%3Cscript%3E'),
      posterUrl: 'https://cdn.example.com/poster.jpg?x=" onerror="bad',
    );

    expect(html, contains('Content-Security-Policy'));
    expect(html, contains("default-src 'none'"));
    expect(html, contains('media-src https:;'));
    expect(html, contains('img-src https: data:;'));
    expect(html, isNot(contains('media-src https: http:')));
    expect(html, contains('referrer" content="no-referrer'));
    expect(html, isNot(contains('autoplay')));
    expect(html, contains("addEventListener('error'"));
    expect(html, contains('DiscourseVideo.postMessage(event)'));
    expect(html, isNot(contains(' onerror="bad')));
    expect(html, contains('poster.jpg?x=%22%20onerror=%22bad'));
  });

  test('Linux document scopes development HTTP to its loopback origin', () {
    final html = buildInlineVideoHtml(
      Uri.parse('http://127.0.0.1:4200/video.mp4'),
      posterUrl: 'http://localhost:4200/poster.jpg',
    );

    expect(html, contains('media-src https: http://127.0.0.1:4200;'));
    expect(html, contains('img-src https: data: http://localhost:4200;'));
    expect(
      () => buildInlineVideoHtml(Uri.parse('http://example.com/video.mp4')),
      throwsA(isA<UnsafeHttpTransportException>()),
    );
  });
}

class _DisposeSpy extends StatefulWidget {
  const _DisposeSpy({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposeSpy> createState() => _DisposeSpyState();
}

class _DisposeSpyState extends State<_DisposeSpy> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}

class _FakeVideoPlayerController extends VideoPlayerController {
  _FakeVideoPlayerController()
    : super.networkUrl(Uri.parse('https://cdn.example.com/demo.mp4')) {
    value = const VideoPlayerValue(
      duration: Duration(seconds: 20),
      position: Duration(seconds: 7),
      size: Size(1280, 720),
      isInitialized: true,
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    value = value.copyWith(isPlaying: false);
  }
}
