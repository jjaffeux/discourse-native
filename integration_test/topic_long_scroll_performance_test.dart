import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:ui' as ui;

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';
import '../test/support/topic_post_list.dart';
import '../test/support/topic_scroll_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile long topic scrolling', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final face
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(face['asset'] as String));
      }
      await loader.load();
    }
    final posts = [
      for (var id = 6001; id <= 6200; id++)
        Post(
          id: id,
          postNumber: id,
          username: 'reader',
          createdAt: DateTime.utc(2026, 8, 1 + (id - 6001) ~/ 8),
          cooked: [
            '<p>Reply $id in a long discussion.</p>',
            if (id % 3 == 0)
              '<blockquote><p>A previous reply with <strong>formatted text</strong>.</p></blockquote>',
            for (var p = 0; p < 2 + id % 5; p++)
              '<p>The reader handles <code>input</code>, <em>emphasis</em>, and an <a href="https://example.com/">ordinary link</a>. Scroll down and back while preserving the reading position.</p>',
            if (id % 4 == 0)
              '<pre><code class="lang-ruby">def process(input)\n  worker.call(input)\nend\n</code></pre>',
            if (id % 5 == 0)
              '<ul><li>Read replies.</li><li>Return to the same position.</li></ul>',
          ].join(),
        ),
    ];
    final api = FakeDiscourseApi(
      topics: {
        7: topicPayload(
          id: 7,
          title: 'Long discussion',
          posts: posts,
          stream: [for (var id = 1; id <= 16000; id++) id],
          postsCount: 16000,
        ),
      },
    );
    final shell = ShellController(
      instanceStore: FakeInstanceStore([instance('scroll.example')]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    addTearDown(shell.dispose);
    await shell.load();
    shell.pushContent(
      ContentRoute.topic(
        topicId: 7,
        slug: 'long',
        title: 'Long discussion',
        postNumber: 6070,
      ),
    );
    await shell.loadTopic(7, 'long', postNumber: 6070);
    expect(shell.currentPostIds, hasLength(200));
    await tester.pumpWidget(
      TopicScrollFixture(controller: shell, inbox: false),
    );
    await tester.pumpAndSettle();
    final list = topicPostList(tester);
    list.listController!.jumpToItem(
      index: 140,
      scrollController: list.controller!,
      alignment: 0,
    );
    await tester.pumpAndSettle();
    final scroll = list.controller!;
    final originPixels = scroll.position.pixels;
    final pagesBefore = api.postFetches.length;
    var updates = 0;
    final excursions = <double>[];
    Future<void> sweep() async {
      for (final delta in [-3600.0, 3600.0]) {
        final legStart = scroll.position.pixels;
        final origin = tester.getCenter(topicPostListFinder());
        final drag = scroll.position.drag(
          DragStartDetails(globalPosition: origin),
          () {},
        );
        final clock = Stopwatch()..start();
        var travelled = 0.0;
        while (clock.elapsedMicroseconds < 1500000) {
          final next =
              delta * (clock.elapsedMicroseconds / 1500000).clamp(0.0, 1.0);
          drag.update(
            DragUpdateDetails(
              globalPosition: origin + Offset(0, next),
              delta: Offset(0, next - travelled),
              primaryDelta: next - travelled,
            ),
          );
          travelled = next;
          updates++;
          await binding.endOfFrame;
        }
        drag.update(
          DragUpdateDetails(
            globalPosition: origin + Offset(0, delta),
            delta: Offset(0, delta - travelled),
            primaryDelta: delta - travelled,
          ),
        );
        drag.end(DragEndDetails(primaryVelocity: 0));
        final excursion = scroll.position.pixels - legStart;
        expect(
          excursion,
          closeTo(-delta, 1),
          reason: 'Each leg must scroll the intended distance',
        );
        excursions.add(excursion);
      }
    }

    await sweep();
    final frames = <ui.FrameTiming>[];
    void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
    final startUs = Timeline.now;
    binding.addTimingsCallback(collect);
    for (var round = 0; round < 3; round++) {
      await sweep();
    }
    final endUs = Timeline.now;
    await Future<void>.delayed(const Duration(seconds: 1));
    binding.removeTimingsCallback(collect);
    frames.removeWhere((f) {
      final t = f.timestampInMicroseconds(ui.FramePhase.buildStart);
      return t < startUs || t > endUs;
    });
    Map<String, Object> summary(Duration Function(ui.FrameTiming) duration) {
      final values =
          frames.map((f) => duration(f).inMicroseconds / 1000).toList()..sort();
      return {
        'meanMs': values.reduce((a, b) => a + b) / values.length,
        'p50Ms': values[(values.length * .5).floor()],
        'p95Ms': values[(values.length * .95).floor()],
        'over8ms': values.where((v) => v > 8.333).length,
      };
    }

    expect(frames.length, greaterThan(100));
    expect(updates, greaterThan(100));
    expect(scroll.position.pixels, closeTo(originPixels, 1));
    expect(api.postFetches.length, pagesBefore);
    expect(shell.currentPostIds, hasLength(200));
    expect(tester.takeException(), isNull);
    final report = <String, Object?>{
      'label': const String.fromEnvironment(
        'PROFILE_LABEL',
        defaultValue: 'current',
      ),
      'frames': frames.length,
      'updates': updates,
      'excursions': excursions,
      'streamPosts': 16000,
      'loadedPosts': shell.currentPostIds.length,
      'physicalSize': [
        tester.view.physicalSize.width,
        tester.view.physicalSize.height,
      ],
      'pixelRatio': tester.view.devicePixelRatio,
      'build': summary((f) => f.buildDuration),
      'raster': summary((f) => f.rasterDuration),
    };
    debugPrint(
      'LONG_TOPIC_SCROLL_PROFILE ${jsonEncode(report)}',
      wrapWidth: 4096,
    );
    binding.reportData = report;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
