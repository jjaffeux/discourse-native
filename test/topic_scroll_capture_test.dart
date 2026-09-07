import 'dart:convert';
import 'dart:ui';

import 'package:discourse_native/src/diagnostics/topic_scroll_capture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps a bounded JSON-safe in-memory topic trace', () async {
    var now = DateTime.utc(2026, 8, 30, 10);
    final capture = TopicScrollCaptureController(
      maximumEvents: 2,
      clock: () => now,
    );
    addTearDown(capture.dispose);

    capture.start();
    capture.recordTopicEvent('scroll.notification', {
      'pixels': 42.5,
      'nonFinite': double.nan,
      'nested': [
        {'token': 'https://example.test/t/1?token=secret'},
      ],
    });
    now = now.add(const Duration(seconds: 1));
    capture.recordTopicEvent('sliver.layout.changed', {
      'visibleRange': [4, 9],
    });

    final state = capture.state;
    expect(state.isRecording, isFalse);
    expect(state.eventCount, 2);
    expect(state.topicEventCount, 2);
    expect(state.duration, const Duration(seconds: 1));
    expect(state.stopReason, TopicScrollCaptureStopReason.eventLimit);

    final encoded = await capture.buildJsonReport();
    final report = jsonDecode(encoded) as Map<String, Object?>;
    final summary = report['summary']! as Map<String, Object?>;
    expect(report['kind'], 'topic-scroll-capture');
    expect(summary['eventCount'], 2);
    expect(encoded, contains('"nonFinite": "NaN"'));
    expect(encoded, isNot(contains('secret')));
  });

  test('captures Flutter build and raster timing alongside topic events', () {
    final capture = TopicScrollCaptureController(
      maximumEvents: 20,
      timelineClock: () => 0,
    );
    addTearDown(capture.dispose);
    capture.start();

    PlatformDispatcher.instance.onReportTimings?.call([
      FrameTiming(
        vsyncStart: 0,
        buildStart: 1000,
        buildFinish: 21000,
        rasterStart: 22000,
        rasterFinish: 47000,
        rasterFinishWallTime: 47000,
        layerCacheCount: 2,
        layerCacheBytes: 2048,
        pictureCacheCount: 3,
        pictureCacheBytes: 4096,
        frameNumber: 42,
      ),
    ]);
    capture.stop();

    expect(capture.state.frameCount, 1);
    expect(capture.state.slowBuildFrameCount, 1);
    expect(capture.state.slowRasterFrameCount, 1);
    final frame = capture.events.singleWhere(
      (event) => event.name == 'frame.timing',
    );
    expect(frame.data['frameNumber'], 42);
    expect(frame.data['buildUs'], 20000);
    expect(frame.data['rasterUs'], 25000);
  });

  test('starting again replaces the previous trace', () {
    final capture = TopicScrollCaptureController();
    addTearDown(capture.dispose);

    capture.start();
    final firstCaptureId = capture.captureId;
    capture.recordTopicEvent('first', const {});
    capture.stop();

    capture.start();
    expect(capture.captureId, firstCaptureId + 1);
    expect(capture.events, isEmpty);
    expect(capture.state.isRecording, isTrue);
    capture.recordTopicEvent('second', const {});
    capture.stop();

    expect(capture.events.map((event) => event.name), ['second']);
    capture.clear();
    expect(capture.state.hasCapture, isFalse);
    expect(capture.events, isEmpty);
  });

  test('uses the display budget and counts UI/raster overruns once', () async {
    final capture = TopicScrollCaptureController(timelineClock: () => 0);
    addTearDown(capture.dispose);
    capture.start(displayRefreshRate: 120);
    PlatformDispatcher.instance.onReportTimings?.call([
      _timing(buildUs: 10000, rasterUs: 4000),
      _timing(buildUs: 6000, rasterUs: 9000),
      _timing(buildUs: 10000, rasterUs: 9000),
    ]);
    capture.stop();

    final report =
        jsonDecode(await capture.buildJsonReport()) as Map<String, Object?>;
    final analysis = report['analysis']! as Map<String, Object?>;
    final frames = analysis['allFrames']! as Map<String, Object?>;
    expect(capture.state.frameBudgetMicroseconds, 8333);
    expect(capture.state.slowBuildFrameCount, 2);
    expect(capture.state.slowRasterFrameCount, 2);
    expect(frames['overBudget'], 3);

    capture.start(displayRefreshRate: double.nan);
    expect(capture.state.displayRefreshRate, 60);
    PlatformDispatcher.instance.onReportTimings?.call([
      _timing(buildUs: 10000, rasterUs: 10000),
    ]);
    capture.stop();
    expect(capture.state.slowBuildFrameCount, 0);
    expect(capture.state.slowRasterFrameCount, 0);
  });

  test('ignores pre-capture frames delivered in a later timing batch', () {
    final capture = TopicScrollCaptureController(timelineClock: () => 10000);
    addTearDown(capture.dispose);
    capture.start();
    PlatformDispatcher.instance.onReportTimings?.call([
      _timing(vsyncStart: 9000, buildUs: 40000),
      _timing(vsyncStart: 10000, buildUs: 2000),
    ]);
    capture.stop();
    expect(capture.state.frameCount, 1);
    expect(capture.state.slowBuildFrameCount, 0);
  });

  test('reports percentiles and bounds the pasteable report', () async {
    final capture = TopicScrollCaptureController(timelineClock: () => 0);
    addTearDown(capture.dispose);
    capture.start();
    PlatformDispatcher.instance.onReportTimings?.call([
      for (var i = 1; i <= 100; i++)
        _timing(vsyncStart: i * 100000, buildUs: i * 1000),
    ]);
    for (var i = 1; i <= 100; i++) {
      capture.recordTopicEvent('post.layout', {
        'topicId': 7,
        'postId': i,
        'htmlCharacters': 5000,
        'durationUs': i * 100,
      });
      capture.recordTopicEvent('viewport.work', {'durationUs': i * 10});
    }
    capture.recordTopicEvent('private-extra-data', {
      'url': 'https://example.test/t/1?token=secret',
      'body': 'PRIVATE POST BODY',
    });
    capture.stop();

    final full = await capture.buildJsonReport();
    final report = jsonDecode(full) as Map<String, Object?>;
    final analysis = report['analysis']! as Map<String, Object?>;
    final frames = analysis['allFrames']! as Map<String, Object?>;
    final builds = frames['buildUs']! as Map<String, Object?>;
    expect(builds['p50'], 50000);
    expect(builds['p95'], 95000);
    expect(builds['p99'], 99000);
    expect(builds['max'], 100000);
    expect(analysis['expensivePosts'], hasLength(8));
    expect(analysis['worstFrames'], hasLength(5));
    expect(full, isNot(contains('secret')));

    final compact = await capture.buildPerformanceReport();
    expect(compact, contains('p95 95.00 ms'));
    expect(compact, contains('Topic 7, post id 100'));
    expect(compact, contains('Viewport bookkeeping: 100 samples'));
    expect(compact, isNot(contains('PRIVATE POST BODY')));
    expect(compact, isNot(contains('example.test')));
    expect(compact.length, lessThan(10000));
  });

  test('matches batched frame timings using engine frame numbers', () async {
    var frameNumber = 42;
    final capture = TopicScrollCaptureController(
      timelineClock: () => 0,
      currentFrameNumber: () => frameNumber,
    );
    addTearDown(capture.dispose);
    capture.start();
    capture.recordTopicEvent('viewport.work', const {'durationUs': 1200});
    frameNumber = 43;
    PlatformDispatcher.instance.onReportTimings?.call([
      _timing(frameNumber: 42, buildUs: 20000),
      _timing(frameNumber: 43, buildUs: 40000),
    ]);
    capture.stop();

    final report =
        jsonDecode(await capture.buildJsonReport()) as Map<String, Object?>;
    final analysis = report['analysis']! as Map<String, Object?>;
    expect((analysis['allFrames']! as Map<String, Object?>)['count'], 2);
    expect((analysis['topicFrames']! as Map<String, Object?>)['count'], 1);
    final worst =
        (analysis['worstFrames']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(worst['buildUs'], 20000);
    expect(worst['topicActivity'], {'viewport.work': 1});
  });

  test('empty capture explains missing measurements', () async {
    final capture = TopicScrollCaptureController();
    addTearDown(capture.dispose);
    capture.start();
    capture.stop();
    final report = await capture.buildPerformanceReport();
    expect(report, contains('No topic context was recorded'));
    expect(report, contains('No frame timings were delivered'));
    expect(report, contains('no samples'));
    expect(report, isNot(contains('NaN')));
  });

  testWidgets(
    'reaching the event limit during layout notifies after the frame',
    (tester) async {
      final capture = TopicScrollCaptureController(maximumEvents: 1);
      addTearDown(capture.dispose);
      capture.start();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ListenableBuilder(
            listenable: capture,
            builder: (context, _) => Column(
              children: [
                Text(capture.isRecording ? 'Recording' : 'Stopped'),
                LayoutBuilder(
                  builder: (context, constraints) {
                    capture.recordTopicEvent('post.layout', const {
                      'durationUs': 1,
                    });
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Stopped'), findsOneWidget);
      expect(capture.state.stopReason, TopicScrollCaptureStopReason.eventLimit);
    },
  );
}

FrameTiming _timing({
  int vsyncStart = 0,
  int buildUs = 1000,
  int rasterUs = 1000,
  int frameNumber = -1,
}) => FrameTiming(
  frameNumber: frameNumber,
  vsyncStart: vsyncStart,
  buildStart: vsyncStart + 1000,
  buildFinish: vsyncStart + 1000 + buildUs,
  rasterStart: vsyncStart + 2000 + buildUs,
  rasterFinish: vsyncStart + 2000 + buildUs + rasterUs,
  rasterFinishWallTime: vsyncStart + 2000 + buildUs + rasterUs,
);
