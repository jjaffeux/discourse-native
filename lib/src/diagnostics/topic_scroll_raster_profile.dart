import 'dart:math' as math;

import 'package:vm_service/vm_service.dart' as vm;

typedef TopicRasterFrame = ({int frameNumber, int startUs, int endUs});

const _frameMarkers = {'Rasterizer::DrawToSurfaces', 'GPURasterizer::Draw'};
// Engine labels only. Arbitrary timeline names and arguments can contain
// widget descriptions, post text, file paths, or debugger connection details.
const _phaseMarkers = {
  'CompositorContext::ScopedFrame::Raster',
  'LayerTree::Preroll',
  'LayerTree::Paint',
  'RasterCache::UpdateCacheEntry',
  'RasterCache::Draw',
  'Canvas::saveLayer',
  'SkCanvas::Flush',
  'GPUSurfaceMetal::Submit',
  'GPUSurfaceMetal::PresentTexture',
  'GPUSurfaceMetalImpeller::AcquireFrame',
  'SurfaceFrame::Submit',
  'SurfaceFrame::Encode',
  'SurfaceFrame::BuildDisplayList',
};

/// Summarizes recorded engine spans on the raster thread matching each frame.
/// This runs on export, with the existing VM timeline streams left untouched.
Map<String, Object?> summarizeTopicRasterProfile(
  vm.Timeline timeline,
  List<TopicRasterFrame> frames,
) {
  final spans = _spans(timeline);
  final roots = spans.where((span) => _frameMarkers.contains(span.name));
  final selected = List.of(frames)
    ..sort((a, b) => (b.endUs - b.startUs).compareTo(a.endUs - a.startUs));
  final profiled = <Map<String, Object?>>[];
  for (final frame in selected.take(20)) {
    final candidates =
        roots
            .where(
              (span) =>
                  _overlap(span.start, span.end, frame.startUs, frame.endUs) >=
                  (frame.endUs - frame.startUs) * 0.9,
            )
            .toList()
          ..sort((a, b) => _distance(a, frame).compareTo(_distance(b, frame)));
    if (candidates.isEmpty) continue;
    final root = candidates.first;
    if (candidates
        .skip(1)
        .any(
          (candidate) =>
              candidate.thread != root.thread &&
              _distance(candidate, frame) == _distance(root, frame),
        )) {
      // Multiple engines can share a VM. Do not guess between equally good
      // frame matches on different raster threads.
      continue;
    }
    final intervals = <String, List<(int, int)>>{};
    for (final span in spans) {
      if (span.thread != root.thread || !_phaseMarkers.contains(span.name)) {
        continue;
      }
      final start = math.max(span.start, frame.startUs);
      final end = math.min(span.end, frame.endUs);
      if (end > start) (intervals[span.name] ??= []).add((start, end));
    }
    final phases =
        intervals.entries
            .map(
              (entry) => (name: entry.key, durationUs: _covered(entry.value)),
            )
            .toList()
          ..sort((a, b) => b.durationUs.compareTo(a.durationUs));
    profiled.add({
      'frameNumber': frame.frameNumber,
      'outsidePhaseMarkersUs':
          frame.endUs -
          frame.startUs -
          _covered(intervals.values.expand((spans) => spans).toList()),
      'phases': [
        for (final phase in phases.take(8))
          {'name': phase.name, 'durationUs': phase.durationUs},
      ],
    });
  }
  return {
    'status': 'available',
    'requestedFrameCount': frames.length,
    'profiledFrameCount': math.min(20, frames.length),
    'matchedFrameCount': profiled.length,
    'frames': profiled,
  };
}

typedef _Span = ({String name, (int, int) thread, int start, int end});

List<_Span> _spans(vm.Timeline timeline) {
  final events =
      [
        for (final (index, event)
            in (timeline.traceEvents ?? <vm.TimelineEvent>[]).indexed)
          if (event.json case final json?) (index: index, data: json),
      ]..sort((a, b) {
        final order = _timestamp(a.data).compareTo(_timestamp(b.data));
        return order == 0 ? a.index.compareTo(b.index) : order;
      });
  final pending = <(int, int), List<Map<String, dynamic>>>{};
  final spans = <_Span>[];
  for (final entry in events) {
    final event = entry.data;
    final timestamp = _timestamp(event);
    if (timestamp < 0 || event['pid'] is! int || event['tid'] is! int) continue;
    final thread = (event['pid'] as int, event['tid'] as int);
    final name = event['name'];
    if (event['ph'] == 'B' && name is String) {
      (pending[thread] ??= []).add(event);
    } else if (event['ph'] == 'E') {
      final stack = pending[thread];
      if (stack == null || stack.isEmpty) continue;
      final index = name is String && name.isNotEmpty
          ? stack.lastIndexWhere((begin) => begin['name'] == name)
          : stack.length - 1;
      if (index < 0) continue;
      final begin = stack[index];
      stack.removeRange(index, stack.length);
      _addSpan(spans, begin['name'], thread, _timestamp(begin), timestamp);
    } else if (event['ph'] == 'X') {
      final duration = event['dur'];
      if (duration is! num || !duration.isFinite || duration < 0) continue;
      _addSpan(spans, name, thread, timestamp, timestamp + duration.toInt());
    }
  }
  return spans;
}

void _addSpan(
  List<_Span> spans,
  Object? name,
  (int, int) thread,
  int start,
  int end,
) {
  if (name is! String ||
      (!_frameMarkers.contains(name) && !_phaseMarkers.contains(name)) ||
      end <= start) {
    return;
  }
  spans.add((name: name, thread: thread, start: start, end: end));
}

int _timestamp(Map<String, dynamic> event) {
  final value = event['ts'];
  return value is num && value.isFinite ? value.toInt() : -1;
}

int _overlap(int a, int b, int c, int d) =>
    math.max(0, math.min(b, d) - math.max(a, c));

int _distance(_Span span, TopicRasterFrame frame) =>
    (span.start - frame.startUs).abs() + (span.end - frame.endUs).abs();

int _covered(List<(int, int)> intervals) {
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  var end = -1;
  var total = 0;
  for (final interval in intervals) {
    total += math.max(0, interval.$2 - math.max(end, interval.$1));
    end = math.max(end, interval.$2);
  }
  return total;
}
