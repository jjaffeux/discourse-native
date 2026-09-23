import 'dart:async';

import 'package:discourse_native/src/shell/inline_video_playback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'support/fake_media_webview.dart';

void main() {
  late FakeMediaWebViewPlatform platform;
  late WebViewPlatform previousPlatform;

  setUp(() {
    previousPlatform = WebViewPlatform.instance ?? FakeMediaWebViewPlatform();
    platform = FakeMediaWebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  tearDown(() => WebViewPlatform.instance = previousPlatform);

  testWidgets(
    'Linux audio transport publishes time, seeks and pauses without browser controls',
    (tester) async {
      final session = createInlineVideoPlaybackSession(
        InlineVideoPlaybackRequest(
          source: Uri.parse('https://example.com/audio.mp3?a=1&b=2'),
          title: 'Audio',
          posterUrl: null,
          aspectRatio: 1,
          siteUrl: null,
          credentials: null,
          lifecycle: null,
          audioOnly: true,
        ),
        platform: TargetPlatform.linux,
      );
      addTearDown(session.dispose);
      await session.start();
      final controller = platform.controllers.single;
      final document = html_parser.parse(controller.documents.single.html);
      expect(document.querySelector('video'), isNull);
      expect(
        document.querySelector('audio')!.attributes['src'],
        'https://example.com/audio.mp3?a=1&b=2',
      );
      expect(
        document.querySelector('audio')!.attributes.containsKey('controls'),
        isFalse,
      );
      controller.channels['DiscourseVideo']!.onMessageReceived(
        const JavaScriptMessage(
          message: '{"playing":true,"position":12.5,"duration":60}',
        ),
      );
      expect(session.state.isPlaying, isTrue);
      expect(session.state.position, const Duration(milliseconds: 12500));
      expect(session.state.duration, const Duration(seconds: 60));
      await session.seekTo(const Duration(seconds: 30));
      expect(controller.scripts.last, contains('currentTime = 30.0'));
      await session.pause();
      expect(
        controller.scripts.last,
        contains("querySelector('audio')?.pause()"),
      );
      expect(session.state.isPlaying, isFalse);
      session.dispose();
      controller.channels['DiscourseVideo']?.onMessageReceived(
        const JavaScriptMessage(message: '{"playing":true}'),
      );
      expect(session.state.isPlaying, isFalse);
    },
  );

  for (final mediaElement in [false, true]) {
    testWidgets(
      '${mediaElement ? 'media' : 'document'} failure during native setup prevents loading a retired player',
      (tester) async {
        final gate = Completer<void>();
        platform.nextGate = (
          MediaWebViewConfigurationStage.navigation,
          gate.future,
        );
        final session = _session();
        addTearDown(session.dispose);
        final starting = session.start();
        await tester.pump();
        final controller = platform.controllers.single;
        if (mediaElement) {
          controller.channels['DiscourseVideo']!.onMessageReceived(
            const JavaScriptMessage(message: 'error'),
          );
        } else {
          controller.delegate!.onWebResourceError!(
            const WebResourceError(
              errorCode: -1,
              description: 'The native WebView failed',
              isForMainFrame: true,
            ),
          );
        }
        expect(session.state.phase, InlineVideoPlaybackPhase.failed);
        gate.complete();
        await starting;

        expect(controller.documents, isEmpty);
        expect(session.state.phase, InlineVideoPlaybackPhase.failed);
        expect(session.state.playerBuilder, isNull);
      },
    );
  }

  testWidgets('the current document becomes playable after native setup', (
    tester,
  ) async {
    final session = _session();
    addTearDown(session.dispose);
    await session.start();
    final controller = platform.controllers.single;
    expect(
      html_parser
          .parse(controller.documents.single.html)
          .querySelector('video')!
          .attributes['src'],
      'https://cdn.example/video.mp4',
    );
    expect(session.state.phase, InlineVideoPlaybackPhase.ready);
    expect(session.state.isBuffering, isTrue);
    final playerBuilder = session.state.playerBuilder;

    controller.delegate!.onPageFinished!('https://cdn.example/');
    await tester.pump();
    controller.channels['DiscourseVideo']!.onMessageReceived(
      const JavaScriptMessage(message: 'play'),
    );

    expect(session.state.isBuffering, isFalse);
    expect(session.state.isPlaying, isTrue);
    expect(session.state.playerBuilder, same(playerBuilder));
    expect(controller.scripts, ["document.querySelector('video')?.play();"]);
    await session.pause();
    expect(session.state.isPlaying, isFalse);
    expect(session.state.playerBuilder, same(playerBuilder));
  });

  testWidgets('pause during document setup cancels pending autoplay', (
    tester,
  ) async {
    final gate = Completer<void>();
    platform.nextGate = (
      MediaWebViewConfigurationStage.navigation,
      gate.future,
    );
    final session = _session();
    addTearDown(session.dispose);
    final starting = session.start();
    await tester.pump();
    final controller = platform.controllers.single;
    await session.pause();
    gate.complete();
    await starting;
    controller.delegate!.onPageFinished!('https://cdn.example/');
    await tester.pump();
    expect(session.state.isPlaying, isFalse);
    expect(controller.scripts, ["document.querySelector('video')?.pause();"]);
    await session.play();
    expect(controller.scripts.last, "document.querySelector('video')?.play();");
  });
}

InlineVideoPlaybackSession _session() => createInlineVideoPlaybackSession(
  InlineVideoPlaybackRequest(
    source: Uri.parse('https://cdn.example/video.mp4'),
    title: 'Video',
    posterUrl: null,
    aspectRatio: 16 / 9,
    siteUrl: null,
    credentials: null,
    lifecycle: null,
  ),
  platform: TargetPlatform.linux,
);
