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

import 'support/blank_png.dart';
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

  testWidgets('a resizing lane shares one decode of the generated frame', (
    tester,
  ) async {
    PaintingBinding.instance.imageCache.clear();
    addTearDown(PaintingBinding.instance.imageCache.clear);
    final harness = _Harness();
    await tester.pumpWidget(harness.app());
    await tester.pump();
    harness.jobs.single.result.complete(blankPng(width: 480, height: 360));
    await _waitForImage(tester);
    // Every lane is wider than the frame, at the test view's 3x density.
    for (var width = 300.0; width < 320; width++) {
      await tester.pumpWidget(harness.app(width: width));
      await _waitForImage(tester);
    }
    expect(harness.jobs, hasLength(1));
    expect(PaintingBinding.instance.imageCache.currentSize, 1);
    expect(PaintingBinding.instance.imageCache.currentSizeBytes, 480 * 360 * 4);
  });

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

  testWidgets('retained offscreen previews do not extract until visible', (
    tester,
  ) async {
    final harness = _Harness();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(harness.retainedApp(scroll: scroll));
    await tester.pumpAndSettle();
    expect(find.byType(InlineVideo), findsNWidgets(2));
    expect(harness.jobs.map((job) => job.source.path), ['/uploads/clip.mp4']);

    scroll.jumpTo(240);
    await tester.pumpAndSettle();
    expect(find.byType(InlineVideo), findsNWidgets(2));
    expect(harness.jobs.first.cancelled, isTrue);
    expect(harness.jobs.map((job) => job.source.path), [
      '/uploads/clip.mp4',
      '/uploads/second.mp4',
    ]);
  });

  testWidgets('retained previews restart unfinished extraction on reentry', (
    tester,
  ) async {
    final harness = _Harness();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(harness.retainedApp(scroll: scroll));
    await tester.pumpAndSettle();
    scroll.jumpTo(240);
    await tester.pumpAndSettle();
    harness.jobs.first.result.complete(emojiPng);
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);

    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(harness.jobs, hasLength(3));
    expect(harness.jobs[1].cancelled, isTrue);
    expect(harness.jobs.last.source.path, '/uploads/clip.mp4');
    harness.jobs.last.result.complete(emojiPng);
    await _waitForImage(tester);
    expect(harness.playerBuilds, 0);
  });

  testWidgets('a remaining visible consumer retains shared extraction', (
    tester,
  ) async {
    final harness = _Harness();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      harness.retainedApp(scroll: scroll, names: const ['clip', 'clip']),
    );
    await tester.pumpAndSettle();
    expect(harness.jobs, hasLength(1));
    scroll.jumpTo(120);
    await tester.pumpAndSettle();
    scroll.jumpTo(240);
    await tester.pumpAndSettle();
    expect(harness.jobs, hasLength(1));
    expect(harness.jobs.single.cancelled, isFalse);
    harness.jobs.single.result.complete(emojiPng);
    await _waitForImage(tester);
  });

  testWidgets('offstage previews wait for visible layout before extraction', (
    tester,
  ) async {
    final harness = _Harness();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      harness.retainedApp(scroll: scroll, offstage: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InlineVideo, skipOffstage: false), findsNWidgets(2));
    expect(harness.jobs, isEmpty);
    await tester.pumpWidget(harness.retainedApp(scroll: scroll));
    await tester.pumpAndSettle();
    expect(harness.jobs, hasLength(1));
    await tester.pumpWidget(
      harness.retainedApp(scroll: scroll, offstage: true),
    );
    await tester.pumpAndSettle();
    expect(harness.jobs.single.cancelled, isTrue);
  });

  testWidgets('ancestor layout changes update retained preview demand', (
    tester,
  ) async {
    final harness = _Harness();
    final scroll = ScrollController();
    final leadingSpace = ValueNotifier(480.0);
    addTearDown(scroll.dispose);
    addTearDown(leadingSpace.dispose);
    await tester.pumpWidget(
      harness.retainedApp(scroll: scroll, leadingSpace: leadingSpace),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InlineVideo), findsNWidgets(2));
    expect(harness.jobs, isEmpty);

    leadingSpace.value = 0;
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(harness.jobs, hasLength(1));
    leadingSpace.value = 480;
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(harness.jobs.single.cancelled, isTrue);
  });

  testWidgets('retained previews reuse completed artwork after reentry', (
    tester,
  ) async {
    final harness = _Harness();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(harness.retainedApp(scroll: scroll));
    await tester.pumpAndSettle();
    harness.jobs.single.result.complete(emojiPng);
    await _waitForImage(tester);
    final original = tester
        .widget<RawImage>(find.byType(RawImage))
        .image!
        .clone();
    addTearDown(original.dispose);
    scroll.jumpTo(240);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await _waitForImage(tester);
    expect(harness.jobs, hasLength(2));
    expect(
      original.isCloneOf(tester.widget<RawImage>(find.byType(RawImage)).image!),
      isTrue,
    );
  });

  testWidgets('viewport reentry respects failed extraction cooldown', (
    tester,
  ) async {
    final harness = _Harness();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(harness.retainedApp(scroll: scroll));
    await tester.pumpAndSettle();
    harness.jobs.single.result.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(find.bySemanticsLabel('Play video: clip.mp4'), findsOneWidget);

    scroll.jumpTo(240);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      harness.jobs.where((job) => job.source.path == '/uploads/clip.mp4'),
      hasLength(1),
    );
    harness.now = harness.now.add(const Duration(seconds: 31));
    scroll.jumpTo(240);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      harness.jobs.where((job) => job.source.path == '/uploads/clip.mp4'),
      hasLength(2),
    );
    harness.jobs.last.result.complete(emojiPng);
    await _waitForImage(tester);
  });

  testWidgets('account replacement rejects retained preview late completion', (
    tester,
  ) async {
    final first = _Harness();
    final replacement = _Harness();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(first.retainedApp(scroll: scroll));
    await tester.pumpAndSettle();
    await tester.pumpWidget(replacement.retainedApp(scroll: scroll));
    await tester.pumpAndSettle();
    expect(first.jobs.single.cancelled, isTrue);
    expect(replacement.jobs, hasLength(1));
    first.jobs.single.result.complete(emojiPng);
    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    replacement.jobs.single.result.complete(emojiPng);
    await _waitForImage(tester);
  });
}

Future<void> _waitForImage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (PaintingBinding.instance.imageCache.pendingImageCount == 0 &&
        find.byType(RawImage).evaluate().isNotEmpty &&
        tester.widget<RawImage>(find.byType(RawImage).first).image != null) {
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
      clock: () => now,
      generator: (source) {
        final job = _Extraction(source);
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
  var now = DateTime.utc(2026, 10, 22);
  var playerBuilds = 0;

  Widget retainedApp({
    required ScrollController scroll,
    List<String> names = const ['clip', 'second'],
    ValueListenable<double>? leadingSpace,
    bool offstage = false,
    double viewportHeight = 240,
  }) {
    final videos = Column(
      children: [
        for (var index = 0; index < names.length; index++)
          SizedBox(
            height: 240,
            child: InlineVideo(
              key: ValueKey('retained-video-$index'),
              data: InlineVideoData.fromUpload(
                url: '/uploads/${names[index]}.mp4',
                title: '${names[index]}.mp4',
                siteUrl: _site,
              )!,
              siteUrl: _site,
              playerBuilder: (_, _) {
                playerBuilds++;
                return const SizedBox.shrink();
              },
            ),
          ),
      ],
    );
    return MaterialApp(
      home: ShellScope(
        controller: shell,
        child: Center(
          child: Offstage(
            offstage: offstage,
            child: SizedBox(
              width: 320,
              height: viewportHeight,
              child: SingleChildScrollView(
                controller: scroll,
                child: leadingSpace == null
                    ? videos
                    : ValueListenableBuilder<double>(
                        valueListenable: leadingSpace,
                        child: videos,
                        builder: (_, height, child) => Column(
                          children: [
                            SizedBox(height: height),
                            child!,
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget app({
    String name = 'clip',
    String? poster,
    bool enabled = true,
    bool scrollable = false,
    double width = 320,
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
              width: width,
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
  _Extraction(this.source);

  final Uri source;
  final result = Completer<Uint8List?>();
  bool cancelled = false;
}
