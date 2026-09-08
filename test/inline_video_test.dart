import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/http_transport.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/video_download.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

import 'support/fakes.dart' show FakeApiCredentialReader;

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

  testWidgets(
    'downloads from the poster and stays busy across playback and full screen',
    (tester) async {
      final gate = Completer<VideoDownloadOutcome>();
      final downloader = _FakeVideoDownloader(() => gate.future);
      final sessions = <_FakePlaybackSession>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: InlineVideo(
              data: _videoData('demo.mp4', 'Demo'),
              siteUrl: 'https://meta.discourse.org',
              videoDownloader: downloader,
              sessionFactory: (request) {
                final session = _FakePlaybackSession(request)..completeReady();
                sessions.add(session);
                return session;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Download video'));
      await tester.pump();
      expect(sessions, isEmpty);
      expect(downloader.calls, 1);
      expect(
        downloader.url,
        Uri.parse('https://meta.discourse.org/uploads/demo.mp4'),
      );
      expect(downloader.title, 'Demo');
      expect(downloader.siteUrl, 'https://meta.discourse.org');
      expect(downloader.shareOrigin?.isEmpty, isFalse);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('inline-video-download')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byTooltip('Downloading video…'));
      expect(downloader.calls, 1);
      await tester.tap(find.bySemanticsLabel('Play video: Demo'));
      await tester.pump();
      expect(sessions, hasLength(1));
      expect(find.byTooltip('Downloading video…'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inline-video-fullscreen')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const ValueKey('inline-video-fullscreen-view')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.descendant(
                of: find.byKey(const ValueKey('inline-video-fullscreen-view')),
                matching: find.byKey(const ValueKey('inline-video-download')),
              ),
            )
            .onPressed,
        isNull,
      );

      gate.complete(VideoDownloadOutcome.saved);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Download video'), findsOneWidget);
      expect(sessions.single.state.isPlaying, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inline-video-fullscreen-view')),
        findsNothing,
      );
      expect(find.text('Saved Demo.mp4.'), findsOneWidget);
      expect(downloader.calls, 1);
    },
  );

  testWidgets('full-screen download uses the same video without pausing it', (
    tester,
  ) async {
    final downloader = _FakeVideoDownloader(
      () async => VideoDownloadOutcome.saved,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: InlineVideo(
            data: _videoData('demo.mp4', 'Demo'),
            siteUrl: 'https://meta.discourse.org',
            videoDownloader: downloader,
            sessionFactory: (request) =>
                _FakePlaybackSession(request)..completeReady(),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Play video: Demo'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('inline-video-fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Download video'));
    await tester.pump();

    expect(downloader.calls, 1);
    expect(find.text('Saved Demo.mp4.'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-player')), findsOneWidget);
  });

  testWidgets('a failed download shows feedback and allows retry', (
    tester,
  ) async {
    var fail = true;
    final downloader = _FakeVideoDownloader(() async {
      if (fail) throw const VideoDownloadException();
      return VideoDownloadOutcome.saved;
    });
    await tester.pumpWidget(_downloadApp(downloader));
    await tester.tap(find.byTooltip('Download video'));
    await tester.pump();
    expect(find.text("Couldn't download video. Try again."), findsOneWidget);
    expect(find.byTooltip('Download video'), findsOneWidget);

    fail = false;
    await tester.tap(find.byTooltip('Download video'));
    await tester.pumpAndSettle();
    expect(downloader.calls, 2);
    expect(find.text('Saved Demo.mp4.'), findsOneWidget);
  });

  for (final outcome in [
    VideoDownloadOutcome.cancelled,
    VideoDownloadOutcome.shared,
  ]) {
    testWidgets('$outcome does not show a saved notification', (tester) async {
      final downloader = _FakeVideoDownloader(() async => outcome);
      await tester.pumpWidget(_downloadApp(downloader));
      await tester.tap(find.byTooltip('Download video'));
      await tester.pumpAndSettle();
      expect(downloader.calls, 1);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byTooltip('Download video'), findsOneWidget);
    });
  }

  testWidgets('download completion after disposal does not update the UI', (
    tester,
  ) async {
    final gate = Completer<VideoDownloadOutcome>();
    await tester.pumpWidget(
      _downloadApp(_FakeVideoDownloader(() => gate.future)),
    );
    await tester.tap(find.byTooltip('Download video'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(VideoDownloadOutcome.saved);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow portrait video keeps both actions inside its preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: InlineVideo(
            data: InlineVideoData.fromUpload(
              url: '/uploads/portrait.mp4',
              title: 'Portrait',
              siteUrl: 'https://meta.discourse.org',
              aspectRatio: 1 / 4,
            )!,
            siteUrl: 'https://meta.discourse.org',
            maximumHeight: 240,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final preview = tester.getRect(
      find.bySemanticsLabel('Play video: Portrait'),
    );
    final play = tester.getRect(
      find.byKey(const ValueKey('inline-video-play')),
    );
    for (final action in [
      find.byTooltip('Download video'),
      find.byTooltip('Open video'),
    ]) {
      final bounds = tester.getRect(action);
      expect(preview.contains(bounds.center), isTrue);
      expect(bounds.left, greaterThanOrEqualTo(preview.left));
      expect(bounds.right, lessThanOrEqualTo(preview.right));
      expect(bounds.overlaps(play), isFalse);
    }
  });

  testWidgets('a playback failure still offers the download button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineVideo(
            data: _videoData('demo.mp4', 'Demo'),
            siteUrl: 'https://meta.discourse.org',
            sessionFactory: (request) => _FakePlaybackSession(request)..fail(),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Play video: Demo'));
    await tester.pump();
    expect(find.text("Couldn't play this video."), findsOneWidget);
    expect(find.byTooltip('Download video'), findsOneWidget);
  });

  testWidgets('session controls keep playback active in a full-screen route', (
    tester,
  ) async {
    final data = InlineVideoData.fromUpload(
      url: '/uploads/demo.mp4',
      title: 'Demo',
      siteUrl: 'https://meta.discourse.org',
    )!;
    late _FakePlaybackSession session;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: InlineVideoPlaybackSurface(
            data: data,
            siteUrl: null,
            credentials: null,
            lifecycle: null,
            sessionFactory: (request) {
              return session = _FakePlaybackSession(request)..completeReady();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const fullscreenButton = ValueKey('inline-video-fullscreen');
    expect(session.state.isPlaying, isTrue);
    expect(
      tester.getSemantics(find.byKey(fullscreenButton)).label,
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
    expect(session.state.isPlaying, isTrue);
    expect(find.byKey(const ValueKey('fake-player')), findsOneWidget);

    const closeButton = ValueKey('inline-video-fullscreen-close');
    expect(
      tester.getSemantics(find.byKey(closeButton)).label,
      'Exit full screen',
    );
    await tester.tap(find.byKey(closeButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-video-fullscreen-view')),
      findsNothing,
    );
    expect(find.byKey(fullscreenButton), findsOneWidget);
    expect(session.state.isPlaying, isTrue);

    await tester.tap(find.byKey(fullscreenButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('inline-video-fullscreen-view')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inline-video-fullscreen-view')),
      findsNothing,
    );
    expect(find.byKey(fullscreenButton), findsOneWidget);
    expect(session.state.isPlaying, isTrue);
  });

  testWidgets('source replacement releases the prior session exactly once', (
    tester,
  ) async {
    final sessions = <_FakePlaybackSession>[];
    final first = _videoData('first.mp4', 'First');
    final second = _videoData('second.mp4', 'Second');

    Widget app(InlineVideoData data) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: InlineVideoPlaybackSurface(
          key: const ValueKey('surface'),
          data: data,
          siteUrl: null,
          credentials: null,
          lifecycle: null,
          sessionFactory: (request) {
            final session = _FakePlaybackSession(request);
            sessions.add(session);
            return session;
          },
        ),
      ),
    );

    await tester.pumpWidget(app(first));
    expect(sessions, hasLength(1));

    await tester.pumpWidget(app(second));
    expect(sessions, hasLength(2));
    expect(sessions.first.disposeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(sessions.first.disposeCount, 1);
    expect(sessions.last.disposeCount, 1);
  });

  for (final changed in ['site', 'credentials', 'lifecycle', 'factory']) {
    testWidgets(
      '$changed replacement moves presentation and controls to the new session',
      (tester) async {
        final sessions = <_FakePlaybackSession>[];
        final data = _videoData('demo.mp4', 'Demo');
        final credentials = FakeApiCredentialReader();
        final replacementCredentials = FakeApiCredentialReader();
        final lifecycle = SiteLifecycle();
        final replacementLifecycle = SiteLifecycle();
        InlineVideoPlaybackSession create(InlineVideoPlaybackRequest request) {
          final session = _FakePlaybackSession(request)..completeReady();
          sessions.add(session);
          return session;
        }

        final InlineVideoPlaybackSessionFactory factory = create;
        InlineVideoPlaybackSession replacementFactory(
          InlineVideoPlaybackRequest request,
        ) => create(request);
        Widget app({required bool replaced}) => MaterialApp(
          home: Scaffold(
            body: InlineVideoPlaybackSurface(
              data: data,
              siteUrl: replaced && changed == 'site'
                  ? 'https://other.example.com'
                  : 'https://meta.discourse.org',
              credentials: replaced && changed == 'credentials'
                  ? replacementCredentials
                  : credentials,
              lifecycle: replaced && changed == 'lifecycle'
                  ? replacementLifecycle
                  : lifecycle,
              sessionFactory: replaced && changed == 'factory'
                  ? replacementFactory
                  : factory,
            ),
          ),
        );

        await tester.pumpWidget(app(replaced: false));
        await tester.pumpWidget(app(replaced: true));
        expect(sessions, hasLength(2));
        expect(sessions.first.disposeCount, 1);
        sessions.first.fail();
        await sessions.first.pause();
        sessions.last.update(position: const Duration(seconds: 11));
        await tester.pump();
        expect(find.text("Couldn't play this video."), findsNothing);
        expect(find.text('0:11 / 0:20'), findsOneWidget);
        await tester.tap(find.byTooltip('Pause'));
        await tester.pump();
        expect(sessions.last.pauseCount, 1);
        expect(find.byTooltip('Play'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(sessions.last.disposeCount, 1);
      },
    );
  }

  testWidgets(
    'control capabilities and a replacement player appear without a new session',
    (tester) async {
      final sessions = <_FakePlaybackSession>[];
      await tester.pumpWidget(
        _sessionApp(_videoData('demo.mp4', 'Demo'), sessions),
      );
      final session = sessions.single..completeReady();
      await tester.pump();
      session.update(showAppControls: false);
      await tester.pump();
      expect(find.byType(Slider), findsNothing);
      expect(find.byTooltip('Pause'), findsNothing);
      session.update(showAppControls: true, supportsFullscreen: false);
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byTooltip('Enter full screen'), findsNothing);
      session.update(
        supportsFullscreen: true,
        playerBuilder: () => const ColoredBox(
          key: ValueKey('replacement-player'),
          color: Colors.blue,
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Enter full screen'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-player')), findsNothing);
      expect(find.byKey(const ValueKey('replacement-player')), findsOneWidget);
      expect(session.startCount, 1);
    },
  );

  testWidgets(
    'parent and inherited changes refresh playback chrome without restarting the session',
    (tester) async {
      final dark = ValueNotifier(false);
      addTearDown(dark.dispose);
      late _FakePlaybackSession session;
      final data = _videoData('demo.mp4', 'Demo');
      InlineVideoPlaybackSession factory(InlineVideoPlaybackRequest request) =>
          session = _FakePlaybackSession(request)..completeReady();
      Widget app(String label) => MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: dark,
            builder: (context, isDark, child) => Theme(
              data: isDark ? AppTheme.dark : AppTheme.light,
              child: child!,
            ),
            child: InlineVideoPlaybackSurface(
              data: data,
              siteUrl: null,
              credentials: null,
              lifecycle: null,
              sessionFactory: factory,
              actionsBuilder: (context) =>
                  Text('$label ${Theme.of(context).brightness.name}'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app('actions'));
      expect(find.text('actions light'), findsOneWidget);
      session.update(
        playerBuilder: () => Builder(
          builder: (context) =>
              Text('player ${Theme.of(context).brightness.name}'),
        ),
      );
      await tester.pump();
      expect(find.text('player light'), findsOneWidget);
      dark.value = true;
      await tester.pump();
      expect(find.text('actions dark'), findsOneWidget);
      expect(find.text('player dark'), findsOneWidget);
      await tester.pumpWidget(app('updated'));
      expect(find.text('updated dark'), findsOneWidget);
      expect(session.startCount, 1);
      expect(session.disposeCount, 0);
    },
  );

  testWidgets('disposal ignores late initialization and releases once', (
    tester,
  ) async {
    final sessions = <_FakePlaybackSession>[];
    await tester.pumpWidget(
      _sessionApp(_videoData('demo.mp4', 'Demo'), sessions),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.single.completeReady();
    sessions.single.fail();
    await tester.pump();

    expect(sessions.single.disposeCount, 1);
    expect(find.byKey(const ValueKey('fake-player')), findsNothing);
    expect(find.text("Couldn't play this video."), findsNothing);
  });

  testWidgets('stale initialization success cannot replace the new source', (
    tester,
  ) async {
    final sessions = <_FakePlaybackSession>[];
    final first = _videoData('first.mp4', 'First');
    final second = _videoData('second.mp4', 'Second');

    await tester.pumpWidget(_sessionApp(first, sessions));
    await tester.pumpWidget(_sessionApp(second, sessions));

    sessions.first.completeReady();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-player')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    sessions.last.completeReady();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-player')), findsOneWidget);
  });

  testWidgets('stale initialization failure cannot replace the new source', (
    tester,
  ) async {
    final sessions = <_FakePlaybackSession>[];
    final first = _videoData('first.mp4', 'First');
    final second = _videoData('second.mp4', 'Second');

    await tester.pumpWidget(_sessionApp(first, sessions));
    await tester.pumpWidget(_sessionApp(second, sessions));

    sessions.first.fail();
    await tester.pump();
    expect(find.text("Couldn't play this video."), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    sessions.last.completeReady();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-player')), findsOneWidget);
  });

  testWidgets('visibility changes pause but do not restart playback', (
    tester,
  ) async {
    final sessions = <_FakePlaybackSession>[];
    await tester.pumpWidget(
      _sessionApp(_videoData('demo.mp4', 'Demo'), sessions),
    );
    sessions.single.completeReady();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(sessions.single.pauseCount, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(sessions.single.pauseCount, 1);
  });

  testWidgets('error UI retries with a fresh session and keeps open fallback', (
    tester,
  ) async {
    final sessions = <_FakePlaybackSession>[];
    await tester.pumpWidget(
      _sessionApp(_videoData('demo.mp4', 'Demo'), sessions),
    );
    sessions.single.fail();
    await tester.pump();

    expect(find.text("Couldn't play this video."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open video'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sessions, hasLength(2));
    expect(sessions.first.disposeCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    sessions.last.completeReady();
    await tester.pump();
    expect(find.byKey(const ValueKey('fake-player')), findsOneWidget);
  });

  testWidgets('unsupported platform renders the external-open fallback', (
    tester,
  ) async {
    final data = _videoData('demo.mp4', 'Demo');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: InlineVideoPlaybackSurface(
            data: data,
            siteUrl: null,
            credentials: null,
            lifecycle: null,
            sessionFactory: (request) => createInlineVideoPlaybackSession(
              request,
              platform: TargetPlatform.windows,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text("Couldn't play this video."), findsOneWidget);
    expect(find.text('Open video'), findsOneWidget);
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

Widget _downloadApp(VideoDownloader downloader) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: InlineVideo(
      data: _videoData('demo.mp4', 'Demo'),
      siteUrl: 'https://meta.discourse.org',
      videoDownloader: downloader,
    ),
  ),
);

class _FakeVideoDownloader implements VideoDownloader {
  _FakeVideoDownloader(this.result);

  final Future<VideoDownloadOutcome> Function() result;
  int calls = 0;
  Uri? url;
  String? title;
  String? siteUrl;
  Rect? shareOrigin;

  @override
  Future<VideoDownloadOutcome> download({
    required Uri url,
    required String title,
    required String? siteUrl,
    required ApiCredentialReader? credentials,
    required SiteLifecycle? lifecycle,
    Rect? sharePositionOrigin,
  }) {
    calls++;
    this.url = url;
    this.title = title;
    this.siteUrl = siteUrl;
    shareOrigin = sharePositionOrigin;
    return result();
  }
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

InlineVideoData _videoData(String filename, String title) =>
    InlineVideoData.fromUpload(
      url: '/uploads/$filename',
      title: title,
      siteUrl: 'https://meta.discourse.org',
    )!;

Widget _sessionApp(InlineVideoData data, List<_FakePlaybackSession> sessions) =>
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: InlineVideoPlaybackSurface(
          key: const ValueKey('surface'),
          data: data,
          siteUrl: null,
          credentials: null,
          lifecycle: null,
          sessionFactory: (request) {
            final session = _FakePlaybackSession(request);
            sessions.add(session);
            return session;
          },
        ),
      ),
    );

final class _FakePlaybackSession implements InlineVideoPlaybackSession {
  _FakePlaybackSession(this.request)
    : _state = InlineVideoPlaybackState(
        phase: InlineVideoPlaybackPhase.initializing,
        aspectRatio: request.aspectRatio,
      );

  final InlineVideoPlaybackRequest request;
  final Set<VoidCallback> _listeners = {};
  InlineVideoPlaybackState _state;
  int startCount = 0;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;

  @override
  InlineVideoPlaybackState get state => _state;

  void completeReady() {
    _state = InlineVideoPlaybackState(
      phase: InlineVideoPlaybackPhase.ready,
      aspectRatio: request.aspectRatio,
      playerBuilder: () =>
          const ColoredBox(key: ValueKey('fake-player'), color: Colors.black),
      isPlaying: true,
      position: const Duration(seconds: 7),
      duration: const Duration(seconds: 20),
      buffered: const Duration(seconds: 12),
      showAppControls: true,
      supportsFullscreen: true,
    );
    _notifyListeners();
  }

  void fail() {
    _state = InlineVideoPlaybackState(
      phase: InlineVideoPlaybackPhase.failed,
      aspectRatio: request.aspectRatio,
      error: StateError('failed'),
    );
    _notifyListeners();
  }

  void update({
    Duration? position,
    bool? showAppControls,
    bool? supportsFullscreen,
    Widget Function()? playerBuilder,
  }) {
    _state = InlineVideoPlaybackState(
      phase: _state.phase,
      aspectRatio: _state.aspectRatio,
      playerBuilder: playerBuilder ?? _state.playerBuilder,
      isPlaying: _state.isPlaying,
      isBuffering: _state.isBuffering,
      position: position ?? _state.position,
      duration: _state.duration,
      buffered: _state.buffered,
      showAppControls: showAppControls ?? _state.showAppControls,
      supportsFullscreen: supportsFullscreen ?? _state.supportsFullscreen,
    );
    _notifyListeners();
  }

  void _notifyListeners() {
    for (final listener in _listeners.toList(growable: false)) {
      listener();
    }
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> play() async {
    playCount++;
    _state = InlineVideoPlaybackState(
      phase: _state.phase,
      aspectRatio: _state.aspectRatio,
      playerBuilder: _state.playerBuilder,
      isPlaying: true,
      position: _state.position,
      duration: _state.duration,
      buffered: _state.buffered,
      showAppControls: _state.showAppControls,
      supportsFullscreen: _state.supportsFullscreen,
    );
    _notifyListeners();
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _state = InlineVideoPlaybackState(
      phase: _state.phase,
      aspectRatio: _state.aspectRatio,
      playerBuilder: _state.playerBuilder,
      isPlaying: false,
      position: _state.position,
      duration: _state.duration,
      buffered: _state.buffered,
      showAppControls: _state.showAppControls,
      supportsFullscreen: _state.supportsFullscreen,
    );
    _notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  void dispose() {
    disposeCount++;
  }
}
