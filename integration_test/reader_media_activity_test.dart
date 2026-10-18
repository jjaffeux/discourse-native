import 'dart:async';

import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets(
    'native decoder retains position across activity and fullscreen',
    (tester) async {
      const fixture = String.fromEnvironment('READER_MEDIA_FIXTURE');
      expect(
        fixture,
        isNotEmpty,
        reason: 'Run tool/check_reader_media_native.py',
      );
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      addTearDown(
        () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );
      final navigator = GlobalKey<NavigatorState>();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      late InlineVideoPlaybackSession session;
      final data = InlineVideoData.fromUpload(
        url: fixture,
        siteUrl: fixture,
        title: 'Native activity fixture',
        posterUrl: null,
        aspectRatio: 16 / 9,
      )!;
      final surface = InlineVideoPlaybackSurface(
        data: data,
        siteUrl: null,
        credentials: null,
        lifecycle: null,
        sessionFactory: (request) =>
            session = createInlineVideoPlaybackSession(request),
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
            child: Center(
              child: SizedBox(width: 600, height: 340, child: surface),
            ),
          ),
        ),
      );
      await _until(
        tester,
        () async =>
            session.state.phase != InlineVideoPlaybackPhase.initializing,
      );
      expect(session.state.error, isNull);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await session.play();
      await _until(tester, () async => session.state.isPlaying);
      await tester.pump();
      final decoder = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      await decoder.setLooping(true);
      await session.seekTo(const Duration(milliseconds: 100));
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 100));
      expect(session.state.isPlaying, isTrue);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await _until(tester, () async => !session.state.isPlaying);
      final pausedAt = session.state.position;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 200));
      expect(session.state.isPlaying, isFalse);
      expect(session.state.position, pausedAt);
      await tester.tap(find.byTooltip('Play'));
      await _until(tester, () async => session.state.isPlaying);
      await tester.tap(find.byKey(const ValueKey('inline-video-fullscreen')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(decoder),
      );
      visible.value = false;
      await tester.pump();
      expect(session.state.isPlaying, isTrue);
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _until(tester, () async => !session.state.isPlaying);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(session.state.isPlaying, isFalse);
      await tester.tap(find.byTooltip('Play'));
      await _until(tester, () async => session.state.isPlaying);
      await tester.tap(
        find.byKey(const ValueKey('inline-video-fullscreen-close')),
      );
      await tester.pumpAndSettle();
      await _until(tester, () async => !session.state.isPlaying);
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
        same(decoder),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('WKWebView obeys source geometry and late iframe events', (
    tester,
  ) async {
    final scroll = ScrollController();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(scroll.dispose);
    addTearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: scroll,
          child: const Column(
            children: [
              YoutubeVideo(
                data: YoutubeVideoData(
                  videoId: 'reader_fixture',
                  listId: null,
                  title: 'Reader browser fixture',
                  thumbnailUrl: null,
                  startSeconds: null,
                  endSeconds: null,
                  loop: false,
                ),
                siteUrl: 'https://forum.example',
              ),
              SizedBox(height: 2500),
            ],
          ),
        ),
      ),
    );
    await tester.tap(
      find.bySemanticsLabel('Play video: Reader browser fixture'),
    );
    await tester.pumpAndSettle();
    final controller = WebViewController.fromPlatform(
      tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller,
    );
    Future<bool> evaluate(String script) async =>
        await controller.runJavaScriptReturningResult(script) == true;
    await _until(
      tester,
      () => evaluate("typeof nativeYoutubeSetVisible === 'function'"),
    );
    await controller.runJavaScript('''
      window.readerDocument = 'retained';
      window.readerPauses = 0;
      window.readerPlays = 0;
      window.readerPlayer = {
        pauseVideo: function() { window.readerPauses++; },
        playVideo: function() { window.readerPlays++; }
      };
      window.YT = {
        Player: function(id, options) {
          window.readerEvents = options.events;
          return window.readerPlayer;
        },
        PlayerState: { PLAYING: 1 }
      };
      window.onYouTubeIframeAPIReady();
      window.onYouTubeIframeAPIReady = function() {};
      window.readerEvents.onReady({target: window.readerPlayer});
    ''');
    await _until(tester, () => evaluate('nativeYoutubeVisible === true'));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(await evaluate('nativeYoutubeVisible === true'), isTrue);
    scroll.jumpTo(1500);
    await tester.pumpAndSettle();
    await _until(
      tester,
      () => evaluate('nativeYoutubeVisible === false && readerPauses > 0'),
    );
    await controller.runJavaScript('''
      window.readerPauses = 0;
      window.readerEvents.onReady({target: window.readerPlayer});
      window.readerEvents.onStateChange({data: 1, target: window.readerPlayer});
    ''');
    expect(await evaluate('readerPauses === 2'), isTrue);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    await _until(tester, () => evaluate('nativeYoutubeVisible === true'));
    expect(
      await evaluate("readerDocument === 'retained' && readerPlays === 0"),
      isTrue,
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await _until(tester, () => evaluate('nativeYoutubeVisible === false'));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _until(tester, () => evaluate('nativeYoutubeVisible === true'));
    expect(await evaluate('readerPlays === 0'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await _until(
      tester,
      () => evaluate("typeof nativeYoutubeSetVisible === 'undefined'"),
    );
  });
}

Future<void> _until(
  WidgetTester tester,
  Future<bool> Function() predicate,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (await predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  fail('The native media condition did not become true.');
}
