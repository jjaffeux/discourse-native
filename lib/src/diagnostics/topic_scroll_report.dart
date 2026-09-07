import 'dart:convert';
import 'dart:math' as math;

import 'diagnostics_redactor.dart';

/// Runs in the export isolate, after recording. No sorting, string scrubbing,
/// or percentile calculation belongs on the scrolling path.
String encodeTopicScrollReport(
  Map<String, Object?> report, {
  required bool compact,
}) {
  final events = _maps(report['events']);
  final summary = _map(report['summary']);
  final budgetUs = _int(summary['slowFrameThresholdUs']);
  final activity = <String, int>{};
  final byFrame = <int, List<Map<String, Object?>>>{};
  final posts = <(int, int), List<int>>{};
  final postLengths = <(int, int), int>{};
  final viewportDurations = <int>[];
  final layoutDurations = <int>[];
  final cpuProfile = _map(report['cpuProfile']);
  final cpuByFrame = {
    for (final frame in _maps(cpuProfile['frames']))
      frame['frameNumber']: frame,
  };
  final rasterTimeline = _map(cpuProfile['rasterTimeline']);
  final rasterByFrame = {
    for (final frame in _maps(rasterTimeline['frames']))
      frame['frameNumber']: frame,
  };
  final contexts = <Map<String, Object?>>[];
  final frames = <Map<String, Object?>>[];

  for (final event in events) {
    final name = event['name'] as String;
    final data = _map(event['data']);
    if (name == 'frame.timing') {
      frames.add(data);
      continue;
    }
    activity.update(name, (count) => count + 1, ifAbsent: () => 1);
    if (event['frameNumber'] case final int frameNumber) {
      (byFrame[frameNumber] ??= []).add(event);
    }
    if (name == 'topic.capture.context') contexts.add(data);
    if (name == 'viewport.work') {
      viewportDurations.add(_int(data['durationUs']));
    }
    if (name == 'post.layout') {
      final duration = _int(data['durationUs']);
      final key = (_int(data['topicId']), _int(data['postId']));
      (posts[key] ??= []).add(duration);
      postLengths[key] = _int(data['htmlCharacters']);
      layoutDurations.add(duration);
    }
  }

  // Timings arrive in batches, and animation timestamps can refer to the
  // target presentation time. The engine frame number joins work to timings
  // without guessing from either timestamp.
  final topicFrames = frames
      .where((frame) => byFrame.containsKey(frame['frameNumber']))
      .toList();
  final rankedFrames = List.of(topicFrames.isEmpty ? frames : topicFrames)
    ..sort((a, b) => _frameCost(b).compareTo(_frameCost(a)));
  final rankedPosts = posts.entries.toList()
    ..sort(
      (a, b) => b.value.reduce(math.max).compareTo(a.value.reduce(math.max)),
    );

  final analysis = <String, Object?>{
    'frameBudgetUs': budgetUs,
    'allFrames': _frameStats(frames, budgetUs),
    'topicFrames': _frameStats(topicFrames, budgetUs),
    'viewportWorkUs': _distribution(viewportDurations),
    'postLayoutUs': _distribution(layoutDurations),
    'activityCounts': activity,
    'topicContextCount': contexts.length,
    'topics': [
      for (final context in contexts.take(8))
        {
          'topicId': context['topicId'],
          'viewportLogicalSize': context['viewportLogicalSize'],
          'devicePixelRatio': context['devicePixelRatio'],
          'loadedPostCount': _map(context['topicWindow'])['loadedPostCount'],
          'streamPostCount': _map(context['topicWindow'])['streamPostCount'],
        },
    ],
    'expensivePosts': [
      for (final entry in rankedPosts.take(8))
        {
          'topicId': entry.key.$1,
          'postId': entry.key.$2,
          'htmlCharacters': postLengths[entry.key],
          'layoutUs': _distribution(entry.value),
        },
    ],
    'worstFrames': [
      for (final frame in rankedFrames.take(5))
        {
          ...frame,
          'topicActivity': _activityCounts(byFrame[frame['frameNumber']] ?? []),
          'measuredWorkUs': {
            for (final name in ['post.layout', 'viewport.work'])
              name: (byFrame[frame['frameNumber']] ?? [])
                  .where((event) => event['name'] == name)
                  .fold<int>(
                    0,
                    (sum, event) =>
                        sum + _int(_map(event['data'])['durationUs']),
                  ),
          },
          'cpu': ?cpuByFrame[frame['frameNumber']],
          'rendering': ?rasterByFrame[frame['frameNumber']],
        },
    ],
  };
  final analyzed = {...report, 'analysis': analysis};
  return compact
      ? DiagnosticsRedactor.scrub(_formatReport(analyzed))
      : const JsonEncoder.withIndent('  ').convert(_jsonSafe(analyzed));
}

Map<String, Object?> _distribution(List<int> values) {
  if (values.isEmpty) return {'count': 0};
  final sorted = List.of(values)..sort();
  int percentile(double p) => sorted[(sorted.length * p).ceil() - 1];
  return {
    'count': sorted.length,
    'total': sorted.fold<int>(0, (sum, value) => sum + value),
    'p50': percentile(0.50),
    'p95': percentile(0.95),
    'p99': percentile(0.99),
    'max': sorted.last,
  };
}

Map<String, Object?> _frameStats(
  List<Map<String, Object?>> frames,
  int budgetUs,
) => {
  'count': frames.length,
  'overBudget': frames.where((frame) => _frameCost(frame) > budgetUs).length,
  'slowBuilds': frames
      .where((frame) => _int(frame['buildUs']) > budgetUs)
      .length,
  'slowRasters': frames
      .where((frame) => _int(frame['rasterUs']) > budgetUs)
      .length,
  for (final field in ['buildUs', 'rasterUs', 'vsyncOverheadUs', 'totalSpanUs'])
    field: _distribution([for (final frame in frames) _int(frame[field])]),
};

int _frameCost(Map<String, Object?> frame) =>
    math.max(_int(frame['buildUs']), _int(frame['rasterUs']));

Map<String, int> _activityCounts(List<Map<String, Object?>> events) {
  final result = <String, int>{};
  for (final event in events) {
    result.update(
      event['name']! as String,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  return result;
}

String _formatReport(Map<String, Object?> report) {
  final app = _map(report['app']);
  final capture = _map(report['capture']);
  final summary = _map(report['summary']);
  final analysis = _map(report['analysis']);
  final allFrames = _map(analysis['allFrames']);
  final topicFrames = _map(analysis['topicFrames']);
  final hasTopicFrames = _int(topicFrames['count']) > 0;
  final measured = hasTopicFrames ? topicFrames : allFrames;
  final output = StringBuffer()
    ..writeln('Topic scrolling performance report (v${report['version']})')
    ..writeln(
      'App: ${app['version'] == '' ? 'local build' : app['version']} | '
      '${app['buildChannel']} | ${app['buildMode']} | ${app['platform']}',
    )
    ..writeln(
      'Recorded: ${capture['startedAtUtc'] ?? 'no capture'} | '
      '${(_int(capture['durationUs']) / 1000000).toStringAsFixed(1)}s | '
      '${capture['status']} (${capture['stopReason'] ?? 'in progress'})',
    )
    ..writeln(
      'Display at start: ${summary['displayRefreshRate']} Hz | '
      'frame budget ${_ms(analysis['frameBudgetUs'])} ms',
    )
    ..writeln(
      'Events: ${summary['eventCount']} | '
      'sampled frames: ${allFrames['count']} | '
      'frames with topic activity: ${topicFrames['count']}',
    )
    ..writeln();

  if (app['buildMode'] == 'debug') {
    output.writeln(
      'Debug build: repeat in a profile or release build to assess '
      'the scrolling performance users experience.',
    );
  }
  if (capture['stopReason'] == 'eventLimit') {
    output.writeln(
      'The event limit ended this capture early. Reproduce with a '
      'shorter capture if the slow moment was missed.',
    );
  }
  if (_int(analysis['topicContextCount']) == 0) {
    output.writeln(
      'No topic context was recorded. Start in the affected topic '
      'and scroll before stopping.',
    );
  }
  if (_int(allFrames['count']) == 0) {
    output.writeln(
      'No frame timings were delivered. Scroll for several seconds '
      'and wait a second before stopping.',
    );
  } else {
    output
      ..writeln(
        hasTopicFrames
            ? 'Frames with topic activity:'
            : 'All sampled app frames (no topic frame matches):',
      )
      ..writeln(
        'Over budget: ${measured['overBudget']}/${measured['count']} '
        '(${(_int(measured['overBudget']) * 100 / _int(measured['count'])).toStringAsFixed(1)}%) | '
        'UI: ${measured['slowBuilds']} | raster: ${measured['slowRasters']}',
      )
      ..writeln(
        'UI build/layout/paint: ${_timingLine(_map(measured['buildUs']))}',
      )
      ..writeln('Raster: ${_timingLine(_map(measured['rasterUs']))}')
      ..writeln(
        'Vsync delay: ${_timingLine(_map(measured['vsyncOverheadUs']))}',
      )
      ..writeln(
        'Total frame latency: ${_timingLine(_map(measured['totalSpanUs']))}',
      );
  }

  output
    ..writeln()
    ..writeln(
      'Viewport bookkeeping: ${_timingLine(_map(analysis['viewportWorkUs']))}',
    )
    ..writeln(
      'Post row layout: ${_timingLine(_map(analysis['postLayoutUs']))}',
    );

  for (final topic in _maps(analysis['topics'])) {
    output.writeln(
      'Topic ${topic['topicId']}: '
      '${topic['loadedPostCount']} loaded / ${topic['streamPostCount']} posts | '
      'viewport ${_map(topic['viewportLogicalSize'])['width']} × '
      '${_map(topic['viewportLogicalSize'])['height']} | '
      'pixel ratio ${topic['devicePixelRatio']}',
    );
  }
  final expensivePosts = _maps(analysis['expensivePosts']);
  if (expensivePosts.isNotEmpty) {
    output
      ..writeln()
      ..writeln('Most expensive post layouts (up to 8, by worst layout):');
    for (final post in expensivePosts) {
      output.writeln(
        '  Topic ${post['topicId']}, post id ${post['postId']}, '
        '${post['htmlCharacters']} HTML characters: '
        '${_timingLine(_map(post['layoutUs']))}',
      );
    }
  }
  _writeCpuProfile(output, _map(report['cpuProfile']));
  _writeRasterProfile(
    output,
    _map(_map(report['cpuProfile'])['rasterTimeline']),
  );
  final worstFrames = _maps(analysis['worstFrames']);
  if (worstFrames.isNotEmpty) {
    output
      ..writeln()
      ..writeln('Worst sampled frames (up to 5, by UI/raster duration):');
    for (final frame in worstFrames) {
      output.writeln(
        '  Frame ${frame['frameNumber'] ?? '?'}: '
        'UI ${_ms(frame['buildUs'])} ms, raster ${_ms(frame['rasterUs'])} ms; '
        '${_countsLine(_map(frame['topicActivity']), limit: 8)}',
      );
      final work = _map(frame['measuredWorkUs']);
      output.writeln(
        '    Measured row layout ${_ms(work['post.layout'])} ms; '
        'viewport ${_ms(work['viewport.work'])} ms',
      );
      final cpu = _map(frame['cpu']);
      if (_int(cpu['sampleCount']) > 0) {
        output.writeln(
          '    CPU (${cpu['sampleCount']} samples): '
          '${_cpuFunctionsLine(cpu, limit: 3)}',
        );
      }
      final rendering = _map(frame['rendering']);
      if (rendering.isNotEmpty) {
        final phases = _maps(rendering['phases']);
        output.writeln(
          '    Rendering: '
          '${phases.isEmpty ? 'no named phases' : phases.map((phase) => '${phase['name']} ${_ms(phase['durationUs'])} ms').join(', ')}; '
          '${_ms(rendering['outsidePhaseMarkersUs'])} ms outside phase markers',
        );
      }
    }
  }
  output
    ..writeln()
    ..writeln(
      'Activity counts: ${_countsLine(_map(analysis['activityCounts']), limit: 24)}',
    )
    ..writeln()
    ..writeln(
      'Interpretation: UI overruns point to build/layout/paint work; '
      'raster overruns point to drawing/compositing. Viewport and row timings '
      'measure those operations only; they do not cover all UI work. '
      'Activity in a slow frame is correlation, not proof of its cause.',
    )
    ..writeln(
      'Timings cover frames delivered before Stop, not idle time or '
      'native compositor stalls. UI and raster overlap; their sum is not a '
      'dropped-frame count. Topic frame matches use engine frame numbers.',
    )
    ..writeln(
      'Post contents, titles, site URLs, and credentials are excluded. '
      'The full JSON capture is available separately.',
    );
  return output.toString();
}

void _writeCpuProfile(StringBuffer output, Map<String, Object?> profile) {
  output.writeln();
  if (profile['status'] != 'available') {
    final reason = switch (profile['reason']) {
      'release-build' => 'CPU sampling requires a debug or profile build.',
      'profiler-disabled' =>
        'Run Flutter with --enable-dart-profiling and capture again.',
      'vm-service-unavailable' =>
        'Start the app with flutter run in debug or profile mode.',
      'capture-in-progress' => 'Stop the capture before exporting CPU samples.',
      'no-capture' => 'No capture has been recorded.',
      _ => 'The Dart VM service could not supply CPU samples.',
    };
    output.writeln('CPU profile unavailable: $reason');
    return;
  }
  final capture = _map(profile['capture']);
  final slow = _map(profile['slowTopicFrames']);
  final hasSlowSamples = _int(slow['sampleCount']) > 0;
  final selected = hasSlowSamples ? slow : capture;
  output.writeln(
    'CPU sampling: ${capture['sampleCount']} capture samples | '
    '${slow['sampleCount']} in slow topic UI frames | '
    'period ${_ms(profile['samplePeriodUs'])} ms',
  );
  if (_int(selected['sampleCount']) == 0) {
    output.writeln(
      'No CPU samples remain for this capture. Copy soon after stopping; '
      'the VM overwrites old samples.',
    );
    return;
  }
  output.writeln(
    hasSlowSamples
        ? 'CPU functions in slow topic frames (exclusive samples):'
        : 'CPU functions across the capture (no slow-frame samples):',
  );
  for (final function in _maps(selected['topFunctions'])) {
    output.writeln('  ${_cpuEntry(function, _int(selected['sampleCount']))}');
  }
  final tags = _maps(selected['vmTags']);
  if (tags.isNotEmpty) {
    output.writeln(
      'CPU runtime tags: '
      '${tags.map((tag) => _cpuEntry(tag, _int(selected['sampleCount']))).join(', ')}',
    );
  }
  output.writeln('Frequent sampled call paths (leaf ← callers):');
  for (final stack in _maps(selected['topStacks']).take(3)) {
    output.writeln('  ${_cpuEntry(stack, _int(selected['sampleCount']))}');
  }
  output.writeln(
    'CPU samples are statistical and may be incomplete. They are not exact '
    'durations; debug compilation, assertions, and GC can appear here.',
  );
}

String _cpuFunctionsLine(Map<String, Object?> summary, {required int limit}) =>
    _maps(summary['topFunctions'])
        .take(limit)
        .map((entry) => _cpuEntry(entry, _int(summary['sampleCount'])))
        .join(', ');

void _writeRasterProfile(StringBuffer output, Map<String, Object?> profile) {
  output.writeln();
  if (profile['status'] != 'available') {
    output.writeln(
      'Rendering timeline unavailable. Run in profile mode to record engine phases.',
    );
    return;
  }
  final requested = _int(profile['requestedFrameCount']);
  if (requested == 0) {
    output.writeln('Rendering timeline: no over-budget topic raster frames.');
    return;
  }
  output.writeln(
    'Rendering timeline: ${profile['matchedFrameCount']}/${profile['profiledFrameCount']} '
    'profiled slow raster frames matched (up to 20 of $requested).',
  );
  if (profile['source'] == 'live-stream') {
    output.writeln(
      'Engine markers retained during capture: ${_int(profile['streamedEventCount'])}; '
      '${_int(profile['retainedEventCount'])} including the final snapshot; '
      '${_int(profile['discardedEventCount'])} discarded at the capture limit.',
    );
    output.writeln(
      'Live timeline collection adds diagnostic overhead during recording.',
    );
    if (profile['tailAvailable'] == false) {
      output.writeln(
        'Final engine snapshot unavailable; the last event block may be missing.',
      );
    }
  } else if (profile['source'] == 'export-buffer') {
    output.writeln(
      'Rendering uses the rolling VM buffer; live recording was unavailable.',
    );
  }
  final unmatched = _maps(profile['unmatchedFrames']);
  for (final frame in unmatched) {
    final reason = switch (frame['reason']) {
      'before-trace-window' => 'older than the retained engine trace',
      'after-trace-window' => 'newer than the retained engine trace',
      'ambiguous-raster-thread' => 'multiple raster threads match',
      'no-frame-markers' => 'no engine frame markers were recorded',
      _ => 'no overlapping engine frame marker',
    };
    output.writeln(
      '  Rendering frame ${frame['frameNumber']} unmatched: $reason.',
    );
  }
  if (_int(profile['matchedFrameCount']) == 0) {
    output.writeln(
      'Rendering data is incomplete; the stall cannot be attributed to an engine phase.',
    );
  } else {
    output.writeln(
      'Rendering phases are recorded engine durations, not GPU execution times. Nested phases overlap; do not add them.',
    );
  }
}

String _cpuEntry(Map<String, Object?> entry, int total) =>
    '${entry['name']} ${entry['samples']}/$total '
    '(${(100 * _int(entry['samples']) / total).toStringAsFixed(1)}%)';

String _timingLine(Map<String, Object?> stats) => _int(stats['count']) == 0
    ? 'no samples'
    : '${stats['count']} samples | p50 ${_ms(stats['p50'])} ms | '
          'p95 ${_ms(stats['p95'])} ms | p99 ${_ms(stats['p99'])} ms | '
          'max ${_ms(stats['max'])} ms';

String _countsLine(Map<String, Object?> counts, {required int limit}) {
  if (counts.isEmpty) return 'none';
  final ranked = counts.entries.toList()
    ..sort((a, b) {
      final order = _int(b.value).compareTo(_int(a.value));
      return order == 0 ? a.key.compareTo(b.key) : order;
    });
  return [
    for (final entry in ranked.take(limit)) '${entry.key}=${entry.value}',
    if (ranked.length > limit)
      '${ranked.length - limit} more event types in JSON',
  ].join(', ');
}

String _ms(Object? value) => (_int(value) / 1000).toStringAsFixed(2);
int _int(Object? value) => value is num && value.isFinite ? value.toInt() : 0;
Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const {};
List<Map<String, Object?>> _maps(Object? value) => value is Iterable<Object?>
    ? value.whereType<Map<String, Object?>>().toList()
    : const [];

Object? _jsonSafe(Object? value) {
  if (value == null || value is bool || value is int) return value;
  if (value is double) return value.isFinite ? value : value.toString();
  if (value is num) return value.toString();
  if (value is String) return DiagnosticsRedactor.scrub(value);
  if (value is Iterable<Object?>) {
    return [for (final item in value) _jsonSafe(item)];
  }
  if (value is Map<Object?, Object?>) {
    return {
      for (final entry in value.entries)
        DiagnosticsRedactor.scrub('${entry.key}'): _jsonSafe(entry.value),
    };
  }
  return DiagnosticsRedactor.safeString(value);
}
