import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:discourse_native/src/diagnostics/topic_scroll_capture.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_cpu_profile.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_raster_profile.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_timeline_recording.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/topic_scroll_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('summarizes chat scrolling without requiring an open topic', () async {
    final capture = topicScrollCaptureWithoutVm();
    addTearDown(capture.dispose);
    capture.start();
    capture.recordTopicEvent('chat.capture.context', {
      'messageCount': 500,
      'thread': false,
      'viewportExtent': 600.0,
    });
    capture.recordTopicEvent('chat.scroll.notification', {'durationUs': 15});
    capture.recordTopicEvent('chat.viewport.work', {'durationUs': 20});
    capture.recordTopicEvent('chat.row.built', {'index': 10});
    capture.stop();

    final report =
        jsonDecode(await capture.buildJsonReport()) as Map<String, Object?>;
    final analysis = report['analysis']! as Map<String, Object?>;
    expect(analysis['chatContextCount'], 1);
    expect((analysis['chatScrollWorkUs']! as Map)['total'], 15);
    expect((analysis['chatViewportWorkUs']! as Map)['total'], 20);
    expect((analysis['activityCounts']! as Map)['chat.row.built'], 1);
    final compact = await capture.buildPerformanceReport();
    expect(compact, contains('500 loaded messages'));
    expect(compact, contains('Chat viewport bookkeeping'));
    expect(compact, isNot(contains('No topic context was recorded')));
  });

  test(
    'summarizes topic-list activity without requiring an open topic',
    () async {
      final capture = topicScrollCaptureWithoutVm();
      addTearDown(capture.dispose);
      capture.start();
      capture.recordTopicEvent('topicList.capture.context', {
        'topicCount': 300,
        'inbox': false,
        'viewportExtent': 600.0,
      });
      capture.recordTopicEvent('topicList.scroll.notification', {
        'durationUs': 25,
        'pixels': 100.0,
      });
      capture.recordTopicEvent('topicList.row.built', {'index': 10});
      capture.stop();

      final report =
          jsonDecode(await capture.buildJsonReport()) as Map<String, Object?>;
      final analysis = report['analysis']! as Map<String, Object?>;
      final work = analysis['topicListScrollWorkUs']! as Map<String, Object?>;
      final activity = analysis['activityCounts']! as Map<String, Object?>;
      expect(analysis['topicListContextCount'], 1);
      expect(work['total'], 25);
      expect(activity['topicList.row.built'], 1);
      final compact = await capture.buildPerformanceReport();
      expect(compact, contains('300 loaded topics'));
      expect(compact, contains('Topic-list scroll bookkeeping'));
      expect(compact, isNot(contains('No topic context was recorded')));
    },
  );

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

  test('reads CPU samples only on export and only once per capture', () async {
    var now = 100;
    var frame = 42;
    final calls = <({int start, int end, List<TopicCpuFrame> frames})>[];
    final rasterCalls = <List<TopicCpuFrame>>[];
    final capture = TopicScrollCaptureController(
      timelineClock: () => now,
      currentFrameNumber: () => frame,
      cpuProfileCollector:
          ({
            required startUs,
            required endUs,
            required slowFrames,
            required slowRasterFrames,
          }) async {
            calls.add((start: startUs, end: endUs, frames: slowFrames));
            rasterCalls.add(slowRasterFrames);
            return {'status': 'available'};
          },
    );
    addTearDown(capture.dispose);
    capture.start(displayRefreshRate: 120);
    capture.recordTopicEvent('post.layout', const {'durationUs': 100});
    frame = 43;
    capture.recordTopicEvent('viewport.work', const {'durationUs': 100});
    PlatformDispatcher.instance.onReportTimings?.call([
      _timing(vsyncStart: 100, frameNumber: 42, buildUs: 20000),
      _timing(
        vsyncStart: 25000,
        frameNumber: 43,
        buildUs: 1000,
        rasterUs: 16000,
      ),
      _timing(vsyncStart: 30000, frameNumber: 44, buildUs: 20000),
    ]);
    await capture.buildPerformanceReport();
    expect(calls, isEmpty);
    now = 60000;
    capture.stop();
    expect(calls, isEmpty);
    await Future.wait([
      capture.buildJsonReport(),
      capture.buildPerformanceReport(),
    ]);
    expect(calls, hasLength(1));
    expect(calls.single.start, 100);
    expect(calls.single.end, 60000);
    expect(calls.single.frames, [
      (frameNumber: 42, startUs: 1100, endUs: 21100),
    ]);
    expect(rasterCalls.single, [
      (frameNumber: 43, startUs: 28000, endUs: 44000),
    ]);
    capture.start();
    now = 70000;
    capture.stop();
    await capture.buildJsonReport();
    expect(calls, hasLength(2));
    expect(calls.last.start, 60000);
    expect(calls.last.end, 70000);
  });

  test('Stop finalizes rendering without waiting for Copy', () async {
    var now = 100;
    final recording = _RasterRecording();
    final capture = TopicScrollCaptureController(
      timelineClock: () => now,
      currentFrameNumber: () => 42,
      rasterRecordingStarter: ({required startUs}) async => recording,
      cpuProfileCollector: _emptyCpuProfile,
    );
    addTearDown(capture.dispose);
    capture.start(displayRefreshRate: 120);
    capture.recordTopicEvent('viewport.work', const {});
    PlatformDispatcher.instance.onReportTimings?.call([
      _timing(vsyncStart: 100, frameNumber: 42, buildUs: 1000, rasterUs: 16000),
    ]);
    now = 40000;
    capture.stop();
    await Future<void>.delayed(Duration.zero);
    expect(recording.calls, 1);
    expect(recording.endUs, 40000);
    expect(recording.frames, [(frameNumber: 42, startUs: 3100, endUs: 19100)]);
    recording.result.complete({'status': 'available', 'source': 'live-stream'});
    final report = jsonDecode(await capture.buildJsonReport()) as Map;
    expect(
      ((report['cpuProfile'] as Map)['rasterTimeline'] as Map)['source'],
      'live-stream',
    );
    await capture.buildPerformanceReport();
    expect(recording.calls, 1);
  });

  test(
    'clearing before the stream connects preserves its Stop request',
    () async {
      var now = 100;
      final started = Completer<TopicRasterRecording>();
      final capture = TopicScrollCaptureController(
        timelineClock: () => now,
        rasterRecordingStarter: ({required startUs}) => started.future,
        cpuProfileCollector: _emptyCpuProfile,
      );
      addTearDown(capture.dispose);
      capture.start();
      now = 200;
      capture.clear();
      final recording = _RasterRecording();
      started.complete(recording);
      await Future<void>.delayed(Duration.zero);
      expect(recording.calls, 1);
      expect(recording.endUs, 200);
      recording.result.complete({'status': 'available'});
      final report = jsonDecode(await capture.buildJsonReport()) as Map;
      expect((report['cpuProfile'] as Map)['reason'], 'no-capture');
    },
  );

  test('a pending rendering result stays with its original capture', () async {
    var now = 100;
    final first = _RasterRecording();
    final second = _RasterRecording();
    final capture = TopicScrollCaptureController(
      timelineClock: () => now,
      rasterRecordingStarter: ({required startUs}) async =>
          startUs == 100 ? first : second,
      cpuProfileCollector: _emptyCpuProfile,
    );
    addTearDown(capture.dispose);
    capture.start();
    now = 200;
    capture.stop();
    final original = capture.buildJsonReport();
    capture.start();
    now = 300;
    capture.dispose();
    first.result.complete({'status': 'available', 'retainedEventCount': 123});
    second.result.complete({'status': 'available', 'retainedEventCount': 456});
    final report = jsonDecode(await original) as Map;
    expect(
      ((report['cpuProfile'] as Map)['rasterTimeline']
          as Map)['retainedEventCount'],
      123,
    );
    expect(first.endUs, 200);
    expect(second.endUs, 300);
  });

  test('a pending CPU export stays attached to its original capture', () async {
    var now = 100;
    final pending = Completer<Map<String, Object?>>();
    final capture = TopicScrollCaptureController(
      timelineClock: () => now,
      cpuProfileCollector:
          ({
            required startUs,
            required endUs,
            required slowFrames,
            required slowRasterFrames,
          }) => pending.future,
    );
    addTearDown(capture.dispose);
    capture.start();
    capture.recordTopicEvent('original-event', const {});
    now = 200;
    capture.stop();
    final report = capture.buildJsonReport();
    capture.start();
    capture.recordTopicEvent('new-event', const {});
    pending.complete({
      'status': 'available',
      'capture': {'sampleCount': 123},
    });
    final encoded = await report;
    expect(encoded, contains('original-event'));
    expect(encoded, isNot(contains('new-event')));
    expect(encoded, contains('123'));
  });

  test(
    'CPU collection failures never expose connection details or break export',
    () async {
      final capture = TopicScrollCaptureController(
        cpuProfileCollector:
            ({
              required startUs,
              required endUs,
              required slowFrames,
              required slowRasterFrames,
            }) => throw StateError('ws://localhost:1234/PRIVATE-TOKEN/ws'),
      );
      addTearDown(capture.dispose);
      capture.start();
      capture.stop();
      final report = await capture.buildJsonReport();
      expect(report, contains('collection-failed'));
      expect(report, isNot(contains('PRIVATE-TOKEN')));
      expect(
        await capture.buildPerformanceReport(),
        contains('CPU profile unavailable'),
      );
    },
  );

  testWidgets(
    'reaching the event limit during layout notifies after the frame',
    (tester) async {
      final capture = topicScrollCaptureWithoutVm(maximumEvents: 1);
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

Future<Map<String, Object?>> _emptyCpuProfile({
  required int startUs,
  required int endUs,
  required List<TopicCpuFrame> slowFrames,
  required List<TopicRasterFrame> slowRasterFrames,
}) async => {'status': 'available'};

final class _RasterRecording implements TopicRasterRecording {
  final result = Completer<Map<String, Object?>>();
  int calls = 0;
  int? endUs;
  List<TopicRasterFrame>? frames;

  @override
  Future<Map<String, Object?>> finish({
    required int endUs,
    required List<TopicRasterFrame> frames,
  }) {
    calls++;
    this.endUs = endUs;
    this.frames = frames;
    return result.future;
  }
}
