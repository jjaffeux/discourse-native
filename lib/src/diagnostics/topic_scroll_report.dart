import 'dart:convert';
import 'dart:math' as math;

import 'package:discourse_native/l10n/strings.dart';

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
  final listScrollDurations = <int>[];
  final listBuildDurations = <int>[];
  final listLayoutDurations = <int>[];
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
  final listContexts = <Map<String, Object?>>[];
  final usersContexts = <Map<String, Object?>>[];
  final usersMaximaDurations = <int>[];
  final extensionContexts = <Map<String, Object?>>[];
  final timings = <String, List<int>>{};
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
    if (name == 'topicList.capture.context') listContexts.add(data);
    if (name == 'users.capture.context') usersContexts.add(data);
    if (name == 'users.maxima.work') {
      usersMaximaDurations.add(_int(data['durationUs']));
    }
    if (name.endsWith('.capture.context') &&
        !const {
          'topic.capture.context',
          'topicList.capture.context',
          'users.capture.context',
        }.contains(name)) {
      extensionContexts.add({'name': name, 'data': data});
    }
    if (data['durationUs'] case final int duration when duration >= 0) {
      (timings[name] ??= []).add(duration);
    }
    if (name == 'topicList.row.build') {
      listBuildDurations.add(_int(data['durationUs']));
    }
    if (name == 'topicList.row.layout') {
      listLayoutDurations.add(_int(data['durationUs']));
    }
    if (name == 'topicList.scroll.notification') {
      listScrollDurations.add(_int(data['durationUs']));
    }
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
    'topicListRowBuildUs': _distribution(listBuildDurations),
    'topicListRowLayoutUs': _distribution(listLayoutDurations),
    'topicListScrollWorkUs': _distribution(listScrollDurations),
    'postLayoutUs': _distribution(layoutDurations),
    'activityCounts': activity,
    'topicContextCount': contexts.length,
    'topicListContextCount': listContexts.length,
    'topicLists': listContexts.take(8).toList(),
    'usersContextCount': usersContexts.length,
    'users': usersContexts.take(8).toList(),
    'usersMaximaWorkUs': _distribution(usersMaximaDurations),
    'extensionContextCount': extensionContexts.length,
    'extensionContexts': extensionContexts.take(8).toList(),
    'timingsUs': {
      for (final entry in timings.entries)
        entry.key: _distribution(entry.value),
    },
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
            for (final name in timings.keys)
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
  final accessibility = _map(capture['accessibility']);
  final summary = _map(report['summary']);
  final analysis = _map(report['analysis']);
  final allFrames = _map(analysis['allFrames']);
  final topicFrames = _map(analysis['topicFrames']);
  final hasTopicFrames = _int(topicFrames['count']) > 0;
  final measured = hasTopicFrames ? topicFrames : allFrames;
  final output = StringBuffer()
    ..writeln(
      appL10n.topicScrollingPerformanceReportV((report['version']).toString()),
    )
    ..writeln(
      appL10n.app(
        (app['version'] == '').toString(),
        (app['buildChannel']).toString(),
        (app['buildMode']).toString(),
        (app['platform']).toString(),
        ((!(app['version'] == '')) ? (app['version']) : '').toString(),
      ),
    )
    ..writeln(
      appL10n.recordedS(
        (capture['startedAtUtc'] ?? appL10n.noCapture).toString(),
        ((_int(capture['durationUs']) / 1000000).toStringAsFixed(1)).toString(),
        (capture['status']).toString(),
        (capture['stopReason'] ?? appL10n.inProgress).toString(),
      ),
    )
    ..writeln(
      appL10n.displayAtStartHzFrameBudgetMs(
        (summary['displayRefreshRate']).toString(),
        (_ms(analysis['frameBudgetUs'])).toString(),
      ),
    )
    ..writeln(
      appL10n.eventsSampledFramesFramesWithTopicActivity(
        (summary['eventCount']).toString(),
        (allFrames['count']).toString(),
        (topicFrames['count']).toString(),
      ),
    )
    ..writeln();

  if (accessibility.isNotEmpty) {
    String enabled(Object? value) => switch (value) {
      true => 'on',
      false => 'off',
      _ => 'unknown',
    };
    output.writeln(
      appL10n.accessibilityAtStartAtEndPlatformRequestStateChanges(
        (enabled(accessibility['frameworkEnabledAtStart'])).toString(),
        (enabled(accessibility['frameworkEnabledAtEnd'])).toString(),
        (enabled(accessibility['platformEnabledAtStart'])).toString(),
        (accessibility['stateChanges']).toString(),
      ),
    );
  }

  if (app['buildMode'] == 'debug') {
    output.writeln(appL10n.debugBuildRepeatInAProfileOrReleaseBuildToAssess);
  }
  if (capture['stopReason'] == 'eventLimit') {
    output.writeln(
      appL10n.theEventLimitEndedThisCaptureEarlyReproduceWithAShorter,
    );
  }
  if (_int(analysis['topicContextCount']) == 0 &&
      _int(analysis['topicListContextCount']) == 0 &&
      _int(analysis['extensionContextCount']) == 0 &&
      _int(analysis['usersContextCount']) == 0) {
    output.writeln(
      appL10n.noContextWasRecordedStartInTheAffectedScreenAndScroll,
    );
  }
  if (_int(allFrames['count']) == 0) {
    output.writeln(
      appL10n.noFrameTimingsWereDeliveredScrollForSeveralSecondsAndWait,
    );
  } else {
    output
      ..writeln(
        hasTopicFrames
            ? appL10n.framesWithScrollActivity
            : appL10n.allSampledAppFramesNoTopicFrameMatches,
      )
      ..writeln(
        appL10n.overBudgetUIRaster(
          (measured['overBudget']).toString(),
          (measured['count']).toString(),
          ((_int(measured['overBudget']) * 100 / _int(measured['count']))
                  .toStringAsFixed(1))
              .toString(),
          (measured['slowBuilds']).toString(),
          (measured['slowRasters']).toString(),
        ),
      )
      ..writeln(
        appL10n.uIBuildLayoutPaint(
          (_timingLine(_map(measured['buildUs']))).toString(),
        ),
      )
      ..writeln(
        appL10n.raster((_timingLine(_map(measured['rasterUs']))).toString()),
      )
      ..writeln(
        appL10n.vsyncDelay(
          (_timingLine(_map(measured['vsyncOverheadUs']))).toString(),
        ),
      )
      ..writeln(
        appL10n.totalFrameLatency(
          (_timingLine(_map(measured['totalSpanUs']))).toString(),
        ),
      );
  }

  output
    ..writeln()
    ..writeln(
      appL10n.viewportBookkeeping(
        (_timingLine(_map(analysis['viewportWorkUs']))).toString(),
      ),
    )
    ..writeln(
      appL10n.postRowLayout(
        (_timingLine(_map(analysis['postLayoutUs']))).toString(),
      ),
    );

  if (_int(analysis['topicListContextCount']) > 0) {
    output.writeln(
      appL10n.topicListScrollBookkeeping(
        (_timingLine(_map(analysis['topicListScrollWorkUs']))).toString(),
      ),
    );
    output
      ..writeln(
        appL10n.topicListRowBuild(
          (_timingLine(_map(analysis['topicListRowBuildUs']))).toString(),
        ),
      )
      ..writeln(
        appL10n.topicListRowLayout(
          (_timingLine(_map(analysis['topicListRowLayoutUs']))).toString(),
        ),
      );
    for (final list in _maps(analysis['topicLists'])) {
      output.writeln(
        appL10n.topicListLoadedTopicsInboxViewportExtent(
          (list['topicCount']).toString(),
          (list['inbox']).toString(),
          (list['viewportExtent']).toString(),
        ),
      );
    }
  }

  if (_int(analysis['usersContextCount']) > 0) {
    for (final users in _maps(analysis['users'])) {
      output.writeln(
        appL10n.usersDirectoryLoadedUsersColumnsViewportExtent(
          (users['rowCount']).toString(),
          (users['columnCount']).toString(),
          (users['viewportExtent']).toString(),
        ),
      );
    }
    output.writeln(
      appL10n.usersMetricMaxima(
        (_timingLine(_map(analysis['usersMaximaWorkUs']))).toString(),
      ),
    );
  }

  for (final entry in _map(analysis['timingsUs']).entries) {
    output.writeln('${entry.key}: ${_timingLine(_map(entry.value))}');
  }
  for (final context in _maps(analysis['extensionContexts'])) {
    output.writeln('${context['name']}: ${jsonEncode(context['data'])}');
  }

  for (final topic in _maps(analysis['topics'])) {
    output.writeln(
      appL10n.topicLoadedPostsViewportPixelRatio(
        (topic['topicId']).toString(),
        (topic['loadedPostCount']).toString(),
        (topic['streamPostCount']).toString(),
        (_map(topic['viewportLogicalSize'])['width']).toString(),
        (_map(topic['viewportLogicalSize'])['height']).toString(),
        (topic['devicePixelRatio']).toString(),
      ),
    );
  }
  final expensivePosts = _maps(analysis['expensivePosts']);
  if (expensivePosts.isNotEmpty) {
    output
      ..writeln()
      ..writeln(appL10n.mostExpensivePostLayoutsUpTo8ByWorstLayout);
    for (final post in expensivePosts) {
      output.writeln(
        appL10n.topicPostIdHTMLCharacters(
          (post['topicId']).toString(),
          (post['postId']).toString(),
          (post['htmlCharacters']).toString(),
          (_timingLine(_map(post['layoutUs']))).toString(),
        ),
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
      ..writeln(appL10n.worstSampledFramesUpTo5ByUIRasterDuration);
    for (final frame in worstFrames) {
      output.writeln(
        appL10n.frameUIMsRasterMs(
          (frame['frameNumber'] ?? '?').toString(),
          (_ms(frame['buildUs'])).toString(),
          (_ms(frame['rasterUs'])).toString(),
          (_countsLine(_map(frame['topicActivity']), limit: 8)).toString(),
        ),
      );
      final work = _map(frame['measuredWorkUs']);
      output.writeln(
        appL10n.measuredRowLayoutMsViewportMsTopicListBuildMsLayout(
          (_ms(work['post.layout'])).toString(),
          (_ms(work['viewport.work'])).toString(),
          (_ms(work['topicList.row.build'])).toString(),
          (_ms(work['topicList.row.layout'])).toString(),
        ),
      );
      final cpu = _map(frame['cpu']);
      if (_int(cpu['sampleCount']) > 0) {
        output.writeln(
          appL10n.cPUSamples(
            (cpu['sampleCount']).toString(),
            (_cpuFunctionsLine(cpu, limit: 3)).toString(),
          ),
        );
      }
      final rendering = _map(frame['rendering']);
      if (rendering.isNotEmpty) {
        final phases = _maps(rendering['phases']);
        output.writeln(
          appL10n.renderingMsOutsidePhaseMarkers(
            (phases.isEmpty).toString(),
            (_ms(rendering['outsidePhaseMarkersUs'])).toString(),
            ((phases.isNotEmpty)
                    ? (phases
                          .map(
                            (phase) => appL10n.msTopicscrollreport(
                              (phase['name']).toString(),
                              (_ms(phase['durationUs'])).toString(),
                            ),
                          )
                          .join(', '))
                    : '')
                .toString(),
          ),
        );
      }
    }
  }
  output
    ..writeln()
    ..writeln(
      appL10n.activityCounts(
        (_countsLine(_map(analysis['activityCounts']), limit: 24)).toString(),
      ),
    )
    ..writeln()
    ..writeln(
      appL10n.interpretationUIOverrunsPointToBuildLayoutPaintWorkRasterOverruns,
    )
    ..writeln(appL10n.timingsCoverFramesDeliveredBeforeStopNotIdleTimeOrNative)
    ..writeln(
      appL10n.postContentsTitlesSiteURLsAndCredentialsAreExcludedTheFull,
    );
  return output.toString();
}

void _writeCpuProfile(StringBuffer output, Map<String, Object?> profile) {
  output.writeln();
  if (profile['status'] != 'available') {
    final reason = switch (profile['reason']) {
      'release-build' => appL10n.cPUSamplingRequiresADebugOrProfileBuild,
      'profiler-disabled' =>
        appL10n.runFlutterWithEnableDartProfilingAndCaptureAgain,
      'vm-service-unavailable' =>
        appL10n.startTheAppWithFlutterRunInDebugOrProfileMode,
      'capture-in-progress' => appL10n.stopTheCaptureBeforeExportingCPUSamples,
      'no-capture' => appL10n.noCaptureHasBeenRecorded,
      _ => appL10n.theDartVMServiceCouldNotSupplyCPUSamples,
    };
    output.writeln(appL10n.cPUProfileUnavailable((reason).toString()));
    return;
  }
  final capture = _map(profile['capture']);
  final slow = _map(profile['slowTopicFrames']);
  final hasSlowSamples = _int(slow['sampleCount']) > 0;
  final selected = hasSlowSamples ? slow : capture;
  output.writeln(
    appL10n.cPUSamplingCaptureSamplesInSlowTopicUIFramesPeriodMs(
      (capture['sampleCount']).toString(),
      (slow['sampleCount']).toString(),
      (_ms(profile['samplePeriodUs'])).toString(),
    ),
  );
  if (_int(selected['sampleCount']) == 0) {
    output.writeln(
      appL10n.noCPUSamplesRemainForThisCaptureCopySoonAfterStopping,
    );
    return;
  }
  output.writeln(
    hasSlowSamples
        ? appL10n.cPUFunctionsInSlowTopicFramesExclusiveSamples
        : appL10n.cPUFunctionsAcrossTheCaptureNoSlowFrameSamples,
  );
  for (final function in _maps(selected['topFunctions'])) {
    output.writeln('  ${_cpuEntry(function, _int(selected['sampleCount']))}');
  }
  final tags = _maps(selected['vmTags']);
  if (tags.isNotEmpty) {
    output.writeln(
      appL10n.cPURuntimeTags(
        (tags
                .map((tag) => _cpuEntry(tag, _int(selected['sampleCount'])))
                .join(', '))
            .toString(),
      ),
    );
  }
  output.writeln(appL10n.frequentSampledCallPathsLeafCallers);
  for (final stack in _maps(selected['topStacks']).take(3)) {
    output.writeln('  ${_cpuEntry(stack, _int(selected['sampleCount']))}');
  }
  output.writeln(appL10n.cPUSamplesAreStatisticalAndMayBeIncompleteTheyAreNot);
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
      appL10n.renderingTimelineUnavailableRunInProfileModeToRecordEnginePhases,
    );
    return;
  }
  final requested = _int(profile['requestedFrameCount']);
  if (requested == 0) {
    output.writeln(appL10n.renderingTimelineNoOverBudgetTopicRasterFrames);
    return;
  }
  output.writeln(
    appL10n.renderingTimelineProfiledSlowRasterFramesMatchedUpTo20Of(
      (profile['matchedFrameCount']).toString(),
      (profile['profiledFrameCount']).toString(),
      (requested).toString(),
    ),
  );
  if (profile['source'] == 'live-stream') {
    output.writeln(
      appL10n
          .engineMarkersRetainedDuringCaptureIncludingTheFinalSnapshotDiscardedAt(
            (_int(profile['streamedEventCount'])).toString(),
            (_int(profile['retainedEventCount'])).toString(),
            (_int(profile['discardedEventCount'])).toString(),
          ),
    );
    output.writeln(
      appL10n.liveTimelineCollectionAddsDiagnosticOverheadDuringRecording,
    );
    if (profile['tailAvailable'] == false) {
      output.writeln(
        appL10n.finalEngineSnapshotUnavailableTheLastEventBlockMayBeMissing,
      );
    }
  } else if (profile['source'] == 'export-buffer') {
    output.writeln(
      appL10n.renderingUsesTheRollingVMBufferLiveRecordingWasUnavailable,
    );
  }
  final unmatched = _maps(profile['unmatchedFrames']);
  for (final frame in unmatched) {
    final reason = switch (frame['reason']) {
      'before-trace-window' => appL10n.olderThanTheRetainedEngineTrace,
      'after-trace-window' => appL10n.newerThanTheRetainedEngineTrace,
      'ambiguous-raster-thread' => appL10n.multipleRasterThreadsMatch,
      'no-frame-markers' => appL10n.noEngineFrameMarkersWereRecorded,
      _ => appL10n.noOverlappingEngineFrameMarker,
    };
    output.writeln(
      appL10n.renderingFrameUnmatched(
        (frame['frameNumber']).toString(),
        (reason).toString(),
      ),
    );
  }
  if (_int(profile['matchedFrameCount']) == 0) {
    output.writeln(
      appL10n.renderingDataIsIncompleteTheStallCannotBeAttributedToAn,
    );
  } else {
    output.writeln(
      appL10n
          .renderingPhasesAreRecordedEngineDurationsNotGPUExecutionTimesNested,
    );
  }
}

String _cpuEntry(Map<String, Object?> entry, int total) =>
    '${entry['name']} ${entry['samples']}/$total '
    '(${(100 * _int(entry['samples']) / total).toStringAsFixed(1)}%)';

String _timingLine(Map<String, Object?> stats) => _int(stats['count']) == 0
    ? appL10n.noSamples
    : appL10n.samplesP50MsP95MsP99MsMaxMs(
        (stats['count']).toString(),
        (_ms(stats['p50'])).toString(),
        (_ms(stats['p95'])).toString(),
        (_ms(stats['p99'])).toString(),
        (_ms(stats['max'])).toString(),
      );

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
      appL10n.moreEventTypesInJSON((ranked.length - limit).toString()),
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
