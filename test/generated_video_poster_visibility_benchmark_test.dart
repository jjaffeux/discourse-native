import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_video_thumbnail_repository.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart' show emojiPng;

const _site = 'https://forum.example';

void main() {
  testWidgets('retained reader poster demand trace', (tester) async {
    for (
      var trial = 0;
      trial < const int.fromEnvironment('POSTER_TRIALS', defaultValue: 5);
      trial++
    ) {
      final harness = _Harness();
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: ShellScope(
            controller: harness.shell,
            child: Center(
              child: SizedBox(
                width: 320,
                height: 220,
                child: SingleChildScrollView(
                  controller: scroll,
                  child: CookedHtml(
                    siteUrl: _site,
                    html: [
                      for (var i = 0; i < 20; i++)
                        '<div class="video-placeholder-container" data-video-src="/uploads/clip-$i.mp4" data-video-title="Clip $i"></div>',
                    ].join(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _drain(tester);
      expect(find.byType(InlineVideo), findsNWidgets(20));
      final retained = tester.element(find.byType(InlineVideo).first);
      stdout.writeln('POSTER_STAGE initial');
      final initial = harness.jobs.map((j) => j.source.path).toList();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await _drain(tester);
      expect(tester.element(find.byType(InlineVideo).first), same(retained));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final visible = tester
          .widgetList<InlineVideo>(find.byType(InlineVideo))
          .where((video) {
            return tester.getRect(find.byWidget(video)).overlaps(viewport);
          })
          .map((video) => video.data.source.path)
          .toSet();
      stdout.writeln('POSTER_STAGE jump');
      final afterJump = harness.jobs.map((j) => j.source.path).toList();
      final cancelledAtJump = harness.jobs.where((j) => j.cancelled).length;
      var waves = 0;
      var useful = false;
      while (!useful && waves < 20) {
        final active = harness.jobs
            .where((j) => !j.cancelled && !j.result.isCompleted)
            .toList();
        expect(active, isNotEmpty);
        for (final job in active) {
          job.result.complete(emojiPng);
          if (visible.contains(job.source.path)) useful = true;
        }
        waves++;
        stdout.writeln('POSTER_STAGE wave-$waves');
        await _drain(tester);
      }
      expect(useful, isTrue);
      if (!const bool.fromEnvironment('POSTER_BASELINE')) {
        expect(waves, 1);
        expect(cancelledAtJump, 2);
        expect(harness.jobs, hasLength(4));
      }
      bool visibleArtwork() => find
          .byType(RawImage)
          .evaluate()
          .any(
            (element) =>
                (element.widget as RawImage).image != null &&
                tester
                    .getRect(find.byWidget(element.widget))
                    .overlaps(viewport),
          );
      for (var i = 0; i < 50 && !visibleArtwork(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(visibleArtwork(), isTrue);
      stdout.writeln(
        'POSTER_TRACE ${jsonEncode({"trial": trial, "mounted": 20, "initialExtracted": initial, "afterJumpExtracted": afterJump, "cancelledAtJump": cancelledAtJump, "visible": visible.toList(), "completionWavesUntilUseful": waves, "totalExtracted": harness.jobs.map((j) => j.source.path).toList(), "errors": 0})}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _drain(tester);
      scroll.dispose();
    }
  });
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

final class _Harness {
  _Harness() {
    final lifecycle = SiteLifecycle();
    final thumbnails = SiteVideoThumbnailRepository(
      credentials: FakeApiCredentialReader(),
      lifecycle: lifecycle,
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
    );
    addTearDown(shell.dispose);
  }

  final jobs = <_Extraction>[];
  late final ShellController shell;
}

final class _Extraction {
  _Extraction(this.source);

  final Uri source;
  final result = Completer<Uint8List?>();
  bool cancelled = false;
}
