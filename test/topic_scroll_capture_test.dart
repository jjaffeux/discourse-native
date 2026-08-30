import 'dart:convert';
import 'dart:ui';

import 'package:discourse_native/src/diagnostics/topic_scroll_capture.dart';
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
    final capture = TopicScrollCaptureController(maximumEvents: 20);
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
}
