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

    controller.delegate!.onPageFinished!('https://cdn.example/');
    await tester.pump();
    controller.channels['DiscourseVideo']!.onMessageReceived(
      const JavaScriptMessage(message: 'play'),
    );

    expect(session.state.isBuffering, isFalse);
    expect(session.state.isPlaying, isTrue);
    expect(controller.scripts, ["document.querySelector('video')?.play();"]);
    await session.pause();
    expect(session.state.isPlaying, isFalse);
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
