import 'dart:async';

import 'package:discourse_native/src/data/site_image_repository.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_video_thumbnail_repository.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show emojiPng;

const _site = 'https://forum.example';
const _poster = '$_site/uploads/poster.png';

void main() {
  for (final failedPoster in [false, true]) {
    testWidgets(
      '${failedPoster ? 'failed' : 'missing'} poster renders a generated frame without starting playback',
      (tester) async {
        final harness = _Harness(posterFails: failedPoster);
        await tester.pumpWidget(
          harness.app(poster: failedPoster ? _poster : null),
        );
        await tester.pumpAndSettle();
        expect(harness.jobs, hasLength(1));
        harness.jobs.single.result.complete(emojiPng);
        await _waitForImage(tester);
        expect(harness.playerBuilds, 0);
        expect(find.bySemanticsLabel('Play video: clip.mp4'), findsOneWidget);
        expect(find.byTooltip('Download video'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('inline-video-play')));
        await tester.pump();
        expect(harness.playerBuilds, 1);
      },
    );
  }

  testWidgets(
    'supplied poster renders without requesting a generated thumbnail',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app(poster: _poster));
      await _waitForImage(tester);
      expect(harness.jobs, isEmpty);
      expect(harness.playerBuilds, 0);
    },
  );

  testWidgets(
    'cached thumbnail renders after remounting without extracting again',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app());
      await tester.pump();
      harness.jobs.single.result.complete(emojiPng);
      await _waitForImage(tester);
      final original = tester
          .widget<RawImage>(find.byType(RawImage))
          .image!
          .clone();
      addTearDown(original.dispose);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(harness.app());
      await _waitForImage(tester);
      expect(harness.jobs, hasLength(1));
      expect(
        original.isCloneOf(
          tester.widget<RawImage>(find.byType(RawImage)).image!,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'replacing a video discards its pending and completed thumbnail',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app());
      await tester.pump();
      await tester.pumpWidget(harness.app(name: 'second'));
      await tester.pump();
      expect(harness.jobs.first.cancelled, isTrue);
      harness.jobs.first.result.complete(emojiPng);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      harness.jobs.last.result.complete(emojiPng);
      await _waitForImage(tester);
      await tester.pumpWidget(harness.app(name: 'third'));
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(harness.playerBuilds, 0);
    },
  );

  testWidgets(
    'hidden panes cancel pending thumbnails and request them when visible',
    (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.app(enabled: false));
      await tester.pump();
      expect(harness.jobs, isEmpty);
      await tester.pumpWidget(harness.app());
      await tester.pump();
      expect(harness.jobs, hasLength(1));
      await tester.pumpWidget(harness.app(enabled: false));
      await tester.pump();
      expect(harness.jobs.single.cancelled, isTrue);
      harness.jobs.single.result.complete(emojiPng);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(harness.app());
      await tester.pump();
      expect(harness.jobs, hasLength(2));
    },
  );

  testWidgets('scrolling a preview out of the list releases its extraction', (
    tester,
  ) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.app(scrollable: true));
    await tester.pump();
    expect(harness.jobs, hasLength(1));
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(harness.jobs.single.cancelled, isTrue);
    expect(find.byType(InlineVideo), findsNothing);
  });
}

Future<void> _waitForImage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.byType(RawImage).evaluate().isNotEmpty &&
        tester.widget<RawImage>(find.byType(RawImage)).image != null) {
      return;
    }
  }
  fail('Thumbnail did not render');
}

final class _Harness {
  _Harness({bool posterFails = false}) {
    final lifecycle = SiteLifecycle();
    final credentials = FakeApiCredentialReader();
    final thumbnails = SiteVideoThumbnailRepository(
      credentials: credentials,
      lifecycle: lifecycle,
      generator: (_) {
        final job = _Extraction();
        jobs.add(job);
        return VideoThumbnailRequest(
          job.result.future,
          () => job.cancelled = true,
        );
      },
    );
    shell = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      lifecycle: lifecycle,
      videoThumbnails: thumbnails,
      siteImages: SiteImageRepository(
        credentials: credentials,
        lifecycle: lifecycle,
        client: MockClient(
          (_) async => http.Response.bytes(emojiPng, posterFails ? 404 : 200),
        ),
      ),
    );
    addTearDown(shell.dispose);
  }

  final jobs = <_Extraction>[];
  late final ShellController shell;
  var playerBuilds = 0;

  Widget app({
    String name = 'clip',
    String? poster,
    bool enabled = true,
    bool scrollable = false,
  }) {
    final video = InlineVideo(
      key: const ValueKey('video'),
      data: InlineVideoData.fromUpload(
        url: '/uploads/$name.mp4',
        title: '$name.mp4',
        siteUrl: _site,
        posterUrl: poster,
      )!,
      siteUrl: _site,
      playerBuilder: (_, _) {
        playerBuilds++;
        return const SizedBox.shrink();
      },
    );
    return MaterialApp(
      home: ShellScope(
        controller: shell,
        child: TickerMode(
          enabled: enabled,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 300,
              child: scrollable
                  ? ListView(
                      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                      children: [video, const SizedBox(height: 1200)],
                    )
                  : video,
            ),
          ),
        ),
      ),
    );
  }
}

final class _Extraction {
  final result = Completer<Uint8List?>();
  bool cancelled = false;
}
