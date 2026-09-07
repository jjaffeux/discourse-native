import 'dart:convert';

import 'package:discourse_native/src/diagnostics/topic_scroll_raster_profile.dart';
import 'package:discourse_native/src/diagnostics/topic_scroll_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;

void main() {
  test(
    'matches rendering phases to their frame and thread without double counting',
    () {
      final profile = summarizeTopicRasterProfile(
        vm.Timeline(
          traceEvents: [
            _event('Rasterizer::DrawToSurfaces', 90, duration: 120),
            _event('CompositorContext::ScopedFrame::Raster', 110, duration: 80),
            _event('SkCanvas::Flush', 120, phase: 'B'),
            _event('PRIVATE POST TEXT', 130, phase: 'B'),
            _event('SkCanvas::Flush', 140, duration: 20),
            _event('PRIVATE POST TEXT', 170, phase: 'E'),
            _event('SkCanvas::Flush', 180, phase: 'E'),
            _event('Rasterizer::DrawToSurfaces', 50, duration: 250, thread: 8),
            _event('SkCanvas::Flush', 100, duration: 100, thread: 8),
          ].reversed.toList(),
        ),
        [(frameNumber: 42, startUs: 100, endUs: 200)],
      );
      expect(profile['matchedFrameCount'], 1);
      final frame = _frames(profile).single;
      expect(frame['outsidePhaseMarkersUs'], 20);
      expect(frame['phases'], [
        {'name': 'CompositorContext::ScopedFrame::Raster', 'durationUs': 80},
        {'name': 'SkCanvas::Flush', 'durationUs': 60},
      ]);
      final encoded = jsonEncode(profile);
      expect(encoded, isNot(contains('PRIVATE')));
      expect(encoded, isNot(contains('example.test')));
      expect(encoded, isNot(contains('pid')));
      expect(encoded, isNot(contains('tid')));
    },
  );

  test(
    'clips phases at frame boundaries and leaves missing spans unmatched',
    () {
      final profile = summarizeTopicRasterProfile(
        vm.Timeline(
          traceEvents: [
            _event('GPURasterizer::Draw', 90, duration: 130),
            _event('SkCanvas::Flush', 50, duration: 70),
            _event('SurfaceFrame::Submit', 180, duration: 70),
            _event('Canvas::saveLayer', 130, phase: 'E'),
            _event('LayerTree::Paint', 150, phase: 'B'),
            _event('LayerTree::Preroll', 130, duration: -1),
          ],
        ),
        [
          (frameNumber: 42, startUs: 100, endUs: 200),
          (frameNumber: 43, startUs: 400, endUs: 500),
        ],
      );
      expect(profile['requestedFrameCount'], 2);
      expect(profile['matchedFrameCount'], 1);
      final frame = _frames(profile).single;
      expect(frame['outsidePhaseMarkersUs'], 60);
      expect(
        frame['phases'],
        unorderedEquals([
          {'name': 'SkCanvas::Flush', 'durationUs': 20},
          {'name': 'SurfaceFrame::Submit', 'durationUs': 20},
        ]),
      );
    },
  );

  test(
    'does not guess between equally close frames from different engines',
    () {
      final profile = summarizeTopicRasterProfile(
        vm.Timeline(
          traceEvents: [
            _event('GPURasterizer::Draw', 90, duration: 120),
            for (final thread in [7, 8])
              _event(
                'Rasterizer::DrawToSurfaces',
                90,
                duration: 120,
                thread: thread,
              ),
          ],
        ),
        [(frameNumber: 42, startUs: 100, endUs: 200)],
      );
      expect(profile['matchedFrameCount'], 0);
    },
  );

  test('bounds rendering analysis to the twenty worst raster frames', () {
    final frames = [
      for (var index = 1; index <= 25; index++)
        (frameNumber: index, startUs: index * 10000, endUs: index * 10100),
    ];
    final profile = summarizeTopicRasterProfile(
      vm.Timeline(
        traceEvents: [
          for (final frame in frames) ...[
            _event(
              'Rasterizer::DrawToSurfaces',
              frame.startUs - 1,
              duration: frame.endUs - frame.startUs + 2,
            ),
            _event(
              'SkCanvas::Flush',
              frame.startUs,
              duration: frame.endUs - frame.startUs,
            ),
          ],
        ],
      ),
      frames,
    );
    expect(profile['requestedFrameCount'], 25);
    expect(profile['profiledFrameCount'], 20);
    expect(profile['matchedFrameCount'], 20);
    expect(_frames(profile).first['frameNumber'], 25);
    expect(_frames(profile).last['frameNumber'], 6);
  });

  test('renders raster evidence even when CPU profiling is unavailable', () {
    final timeline = summarizeTopicRasterProfile(
      vm.Timeline(
        traceEvents: [
          _event('Rasterizer::DrawToSurfaces', 99, duration: 20002),
          _event('SkCanvas::Flush', 100, duration: 18000),
        ],
      ),
      [(frameNumber: 42, startUs: 100, endUs: 20100)],
    );
    final report = encodeTopicScrollReport({
      'version': 4,
      'summary': {'slowFrameThresholdUs': 8333},
      'cpuProfile': {'status': 'unavailable', 'rasterTimeline': timeline},
      'events': [
        {
          'name': 'frame.timing',
          'data': {'frameNumber': 42, 'buildUs': 1000, 'rasterUs': 20000},
        },
        {
          'name': 'viewport.work',
          'frameNumber': 42,
          'data': {'durationUs': 20},
        },
      ],
    }, compact: true);
    expect(report, contains('performance report (v4)'));
    expect(report, contains('CPU profile unavailable'));
    expect(report, contains('Rendering timeline: 1/1'));
    expect(report, contains('SkCanvas::Flush 18.00 ms'));
    expect(report, contains('2.00 ms outside phase markers'));
    expect(report, contains('Nested phases overlap'));
  });
}

List<Map<String, Object?>> _frames(Map<String, Object?> profile) =>
    (profile['frames']! as List).cast<Map<String, Object?>>();

vm.TimelineEvent _event(
  String name,
  int timestamp, {
  int thread = 7,
  String phase = 'X',
  int? duration,
}) => vm.TimelineEvent.parse({
  'name': name,
  'ts': timestamp,
  'tid': thread,
  'pid': 123,
  'ph': phase,
  'dur': ?duration,
  'args': {
    'url': 'https://example.test/PRIVATE-TOKEN',
    'text': 'PRIVATE POST TEXT',
  },
})!;
