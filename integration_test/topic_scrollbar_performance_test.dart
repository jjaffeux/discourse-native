import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

import '../test/support/fakes.dart';
import '../test/support/topic_post_list.dart';
import '../test/support/topic_scroll_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('profile desktop topic scrollbar thumb dragging', (tester) async {
    expect(Platform.isMacOS, isTrue, reason: 'Run on the native macOS engine');
    expect(defaultTargetPlatform, TargetPlatform.macOS);
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
      for (var n = 1; n <= 200; n++)
        Post(
          id: 6000 + n,
          postNumber: n,
          username: 'reader',
          createdAt: DateTime.utc(2026, 8, 1 + n ~/ 8),
          cooked: [
            '<p>Reply $n in a long discussion.</p>',
            if (n % 3 == 0)
              '<blockquote><p>A previous reply with <strong>formatted text</strong>.</p></blockquote>',
            for (var p = 0; p < 2 + n % 5 + (n % 13 == 0 ? 60 : 0); p++)
              '<p>The reader handles <code>input</code>, <em>emphasis</em>, and an <a href="https://example.com/">ordinary link</a>. Scroll down and back while preserving the reading position.</p>',
            if (n % 4 == 0)
              '<pre><code class="lang-ruby">def process(input)\n  worker.call(input)\nend\n</code></pre>',
            if (n % 5 == 0)
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
          stream: [for (final post in posts) post.id],
          postsCount: posts.length,
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
      ContentRoute.topic(topicId: 7, slug: 'long', title: 'Long discussion'),
    );
    await shell.loadTopic(7, 'long');
    expect(shell.currentPostIds, [for (final post in posts) post.id]);
    await tester.pumpWidget(
      TopicScrollFixture(controller: shell, inbox: false),
    );
    await const MethodChannel(
      'org.discourse.native/window',
    ).invokeMethod<void>('dismissLaunchScreen');
    await tester.pumpAndSettle();
    final scroll = topicPostList(tester).controller!;
    final bar = find.byWidgetPredicate(
      (widget) => widget is DScrollBar && widget.controller == scroll,
    );
    expect(bar, findsOneWidget);
    final raw = find.descendant(
      of: bar,
      matching: find.byWidgetPredicate(
        (widget) => widget is RawScrollbar && widget.controller == scroll,
      ),
    );
    expect(raw, findsOneWidget);
    final paint = find
        .descendant(
          of: raw,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.foregroundPainter is ScrollbarPainter,
          ),
        )
        .first;
    final painter =
        tester.widget<CustomPaint>(paint).foregroundPainter!
            as ScrollbarPainter;
    final pagesBefore = api.postFetches.length;
    final phases = <String, Object?>{};
    binding.reportData = {};
    const profileCpu = bool.fromEnvironment('PROFILE_CPU');
    vm.VmService? service;
    {
      final uri = (await developer.Service.getInfo()).serverUri!;
      service = await vmServiceConnectUri(
        'ws://localhost:${uri.port}${uri.path}ws',
      );
      await service.setFlag('profiler', '$profileCpu');
      if (profileCpu) await service.setFlag('profile_period', '250');
      addTearDown(service.dispose);
    }
    final isolateId = developer.Service.getIsolateId(Isolate.current)!;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    Future<void> measure(String name, double targetFraction) async {
      final bounds = tester.getRect(paint);
      final x =
          bounds.width -
          DScrollThumb.containerInset -
          DScrollThumb.defaultThickness / 2;
      await mouse.moveTo(bounds.topLeft + Offset(x, bounds.height / 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final thumbPixels = [
        for (var y = 0; y < bounds.height; y++)
          if (painter.hitTestOnlyThumbInteractive(
            Offset(x, y.toDouble()),
            PointerDeviceKind.mouse,
          ))
            y.toDouble(),
      ];
      expect(thumbPixels, isNotEmpty, reason: 'The painted thumb must be hit');
      final origin =
          bounds.topLeft +
          Offset(x, (thumbPixels.first + thumbPixels.last) / 2);
      final target = bounds.topLeft + Offset(x, bounds.height * targetFraction);
      final before = scroll.offset;
      final visibleBefore = _visiblePost(tester);
      final frames = <ui.FrameTiming>[];
      final inputMicros = <int>[];
      void collect(List<ui.FrameTiming> batch) => frames.addAll(batch);
      if (profileCpu) await service!.clearCpuSamples(isolateId);
      await mouse.moveTo(origin);
      binding.addTimingsCallback(collect);
      final startUs = developer.Timeline.now;
      final clock = Stopwatch()..start();
      var updates = 0;
      await mouse.down(origin);
      try {
        while (clock.elapsedMicroseconds < 1500000) {
          final fraction = (clock.elapsedMicroseconds / 1500000).clamp(
            0.0,
            1.0,
          );
          final input = Stopwatch()..start();
          await mouse.moveTo(Offset.lerp(origin, target, fraction)!);
          inputMicros.add(input.elapsedMicroseconds);
          updates++;
          await binding.endOfFrame;
        }
        await mouse.moveTo(target);
        updates++;
        await binding.endOfFrame;
      } finally {
        await mouse.up();
      }
      final endUs = developer.Timeline.now;
      final after = scroll.offset;
      final visibleAfter = _visiblePost(tester);
      await Future<void>.delayed(const Duration(seconds: 1));
      binding.removeTimingsCallback(collect);
      frames.removeWhere((frame) {
        final t = frame.timestampInMicroseconds(ui.FramePhase.buildStart);
        return t < startUs || t > endUs;
      });
      expect(frames.length, greaterThan(20), reason: name);
      expect(
        frames.any((frame) => frame.rasterDuration.inMicroseconds > 100),
        isTrue,
        reason: 'The native engine must rasterize the topic during $name',
      );
      expect(updates, greaterThan(20), reason: name);
      expect((after - before).abs(), greaterThan(5000), reason: name);
      expect(
        (visibleAfter - visibleBefore).abs(),
        greaterThan(10),
        reason: name,
      );
      expect(after - before, targetFraction > .5 ? isPositive : isNegative);
      expect(api.postFetches.length, pagesBefore, reason: name);
      expect(tester.takeException(), isNull, reason: name);
      final phase = <String, Object?>{
        'wallMs': (endUs - startUs) / 1000,
        'updates': updates,
        'frames': frames.length,
        'offsetBefore': before,
        'offsetAfter': after,
        'visiblePostBefore': visibleBefore,
        'visiblePostAfter': visibleAfter,
        'inputDispatch': _summary(
          inputMicros.map(
            (microseconds) => Duration(microseconds: microseconds),
          ),
        ),
        'build': _summary(frames.map((f) => f.buildDuration)),
        'raster': _summary(frames.map((f) => f.rasterDuration)),
        'total': _summary(frames.map((f) => f.totalSpan)),
      };
      phases[name] = phase;
      binding.reportData!['frameTimings.$name'] = [
        for (final frame in frames)
          [
            frame.timestampInMicroseconds(ui.FramePhase.buildStart),
            frame.buildDuration.inMicroseconds,
            frame.rasterDuration.inMicroseconds,
          ],
      ];
      if (profileCpu) {
        final samples = await service!.getCpuSamples(
          isolateId,
          startUs,
          endUs - startUs,
        );
        phase['cpuSamples'] = samples.sampleCount;
        binding.reportData!['cpuFolded.$name'] = _folded(samples);
      }
      debugPrint(
        'TOPIC_SCROLLBAR_PHASE $name ${jsonEncode(phase)}',
        wrapWidth: 8192,
      );
    }

    await measure('coldDown', .8);
    await measure('warmUp', .2);
    await measure('warmDown', .8);
    await measure('warmUpAgain', .2);
    expect(shell.currentPostIds, [for (final post in posts) post.id]);
    final report = <String, Object?>{
      'label': const String.fromEnvironment(
        'PROFILE_LABEL',
        defaultValue: 'current',
      ),
      'profileMode': kProfileMode,
      'profileCpu': profileCpu,
      'platform': defaultTargetPlatform.name,
      'physicalSize': [
        tester.view.physicalSize.width,
        tester.view.physicalSize.height,
      ],
      'pixelRatio': tester.view.devicePixelRatio,
      'loadedPosts': shell.currentPostIds.length,
      'streamPosts': posts.length,
      'pageFetchesDuringDrag': api.postFetches.length - pagesBefore,
      'phases': phases,
    };
    binding.reportData!['summary'] = report;
    debugPrint(
      'TOPIC_SCROLLBAR_PROFILE ${jsonEncode(report)}',
      wrapWidth: 16384,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, semanticsEnabled: false);
}

int _visiblePost(WidgetTester tester) {
  final viewport = topicReadingViewportRect(tester);
  final visible = <int>[];
  for (final element in tester.allElements) {
    final key = element.widget.key;
    if (key is! ValueKey<int> || key.value < 6001 || key.value > 6200) continue;
    final render = element.findRenderObject();
    if (render is! RenderBox || !render.hasSize) continue;
    final bounds = render.localToGlobal(Offset.zero) & render.size;
    if (bounds.overlaps(viewport)) visible.add(key.value - 6000);
  }
  expect(
    visible,
    isNotEmpty,
    reason: 'A real topic post must occupy the viewport',
  );
  return visible.reduce((a, b) => a < b ? a : b);
}

Map<String, Object> _summary(Iterable<Duration> durations) {
  final values = [for (final d in durations) d.inMicroseconds / 1000]..sort();
  double at(double q) =>
      values[(values.length * q).floor().clamp(0, values.length - 1)];
  return {
    'meanMs': values.reduce((a, b) => a + b) / values.length,
    'p50Ms': at(.5),
    'p95Ms': at(.95),
    'p99Ms': at(.99),
    'maxMs': values.last,
    'over8ms': values.where((v) => v > 8.333).length,
    'over16ms': values.where((v) => v > 16.667).length,
  };
}

String _folded(vm.CpuSamples samples) {
  final names = [
    for (final profile in samples.functions ?? const <vm.ProfileFunction>[])
      switch (profile.function) {
        vm.FuncRef(:final name, owner: vm.ClassRef(name: final owner)) =>
          '$owner.$name',
        vm.FuncRef(:final name) => '$name',
        vm.NativeFunction(:final name) => '$name',
        _ => profile.kind ?? '?',
      }.replaceAll(';', ':').replaceAll(' ', '_'),
  ];
  final counts = <String, int>{};
  for (final sample in samples.samples ?? const <vm.CpuSample>[]) {
    final stack = sample.stack;
    if (stack == null || stack.isEmpty) continue;
    final key = [
      for (final index in stack.reversed)
        index < names.length ? names[index] : '?',
    ].join(';');
    counts.update(key, (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final entry in counts.entries) '${entry.key} ${entry.value}',
  ].join('\n');
}
