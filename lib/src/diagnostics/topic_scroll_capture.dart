import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../data/app_release.dart';
import '../foundation/frame_safe_notifier.dart';
import 'topic_scroll_report.dart';

enum TopicScrollCaptureStopReason { manual, durationLimit, eventLimit }

@immutable
final class TopicScrollCaptureState {
  const TopicScrollCaptureState({
    required this.isRecording,
    required this.hasCapture,
    required this.eventCount,
    required this.topicEventCount,
    required this.frameCount,
    required this.slowBuildFrameCount,
    required this.slowRasterFrameCount,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.duration,
    required this.stopReason,
    required this.displayRefreshRate,
    required this.frameBudgetMicroseconds,
  });

  final bool isRecording;
  final bool hasCapture;
  final int eventCount;
  final int topicEventCount;
  final int frameCount;
  final int slowBuildFrameCount;
  final int slowRasterFrameCount;
  final DateTime? startedAtUtc;
  final DateTime? endedAtUtc;
  final Duration? duration;
  final TopicScrollCaptureStopReason? stopReason;
  final double displayRefreshRate;
  final int frameBudgetMicroseconds;
}

@immutable
final class TopicScrollCaptureEvent {
  const TopicScrollCaptureEvent({
    required this.sequence,
    required this.elapsedMicroseconds,
    required this.category,
    required this.name,
    required this.data,
    this.frameNumber,
  });

  final int sequence;
  final int elapsedMicroseconds;
  final String category;
  final String name;
  final Map<String, Object?> data;
  final int? frameNumber;

  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'elapsedUs': elapsedMicroseconds,
    'category': category,
    'name': name,
    if (frameNumber != null) 'frameNumber': frameNumber,
    if (data.isNotEmpty) 'data': data,
  };
}

/// High-frequency scroll and sliver observations deliberately do not enter the
/// ordinary diagnostics timeline. That timeline persists every event, and the
/// I/O plus per-event UI notification would contaminate the performance being
/// measured. This recorder only allocates while explicitly armed, never writes
/// to disk, and publishes state only when capture starts or stops.
final class TopicScrollCaptureController extends FrameSafeNotifier {
  TopicScrollCaptureController({
    this.maximumEvents = defaultMaximumEvents,
    this.maximumDuration = defaultMaximumDuration,
    DateTime Function()? clock,
    int Function()? timelineClock,
    int? Function()? currentFrameNumber,
  }) : assert(maximumEvents > 0),
       assert(maximumDuration > Duration.zero),
       _clock = clock ?? _utcNow,
       _timelineClock = timelineClock ?? (() => developer.Timeline.now),
       _currentFrameNumber = currentFrameNumber ?? _readCurrentFrameNumber;

  static const int reportFormatVersion = 2;
  static const int defaultMaximumEvents = 12000;
  static const Duration defaultMaximumDuration = Duration(minutes: 2);
  static const Duration slowFrameThreshold = Duration(microseconds: 16667);

  final int maximumEvents;
  final Duration maximumDuration;
  final DateTime Function() _clock;
  final int Function() _timelineClock;
  final int? Function() _currentFrameNumber;
  final List<TopicScrollCaptureEvent> _events = [];
  final Stopwatch _elapsed = Stopwatch();

  Timer? _durationTimer;
  DateTime? _startedAtUtc;
  DateTime? _endedAtUtc;
  TopicScrollCaptureStopReason? _stopReason;
  bool _recording = false;
  bool _timingsAttached = false;
  bool _disposed = false;
  int _captureId = 0;
  int _sequence = 0;
  int _topicEventCount = 0;
  int _frameCount = 0;
  int _slowBuildFrameCount = 0;
  int _slowRasterFrameCount = 0;
  int _maximumBuildMicroseconds = 0;
  int _maximumRasterMicroseconds = 0;
  int _maximumTotalSpanMicroseconds = 0;
  int _startedAtTimelineUs = 0;
  double _displayRefreshRate = 60;
  int _frameBudgetUs = slowFrameThreshold.inMicroseconds;

  bool get isRecording => _recording;

  /// Changes for every new recording, allowing a topic to emit its context
  /// once per capture without subscribing the viewport to recorder state.
  int get captureId => _captureId;

  List<TopicScrollCaptureEvent> get events => List.unmodifiable(_events);

  TopicScrollCaptureState get state {
    final started = _startedAtUtc;
    final ended = _endedAtUtc;
    return TopicScrollCaptureState(
      isRecording: _recording,
      hasCapture: started != null,
      eventCount: _events.length,
      topicEventCount: _topicEventCount,
      frameCount: _frameCount,
      slowBuildFrameCount: _slowBuildFrameCount,
      slowRasterFrameCount: _slowRasterFrameCount,
      startedAtUtc: started,
      endedAtUtc: ended,
      duration: started == null
          ? null
          : (ended ?? _clock().toUtc()).difference(started),
      stopReason: _stopReason,
      displayRefreshRate: _displayRefreshRate,
      frameBudgetMicroseconds: _frameBudgetUs,
    );
  }

  void start({double? displayRefreshRate}) {
    if (_disposed) return;
    if (_recording) _stop(TopicScrollCaptureStopReason.manual, notify: false);
    _events.clear();
    _sequence = 0;
    _topicEventCount = 0;
    _frameCount = 0;
    _slowBuildFrameCount = 0;
    _slowRasterFrameCount = 0;
    _maximumBuildMicroseconds = 0;
    _maximumRasterMicroseconds = 0;
    _maximumTotalSpanMicroseconds = 0;
    _displayRefreshRate =
        displayRefreshRate != null &&
            displayRefreshRate.isFinite &&
            displayRefreshRate >= 1 &&
            displayRefreshRate <= 1000
        ? displayRefreshRate
        : 60;
    _frameBudgetUs = (1000000 / _displayRefreshRate).round().clamp(1, 1000000);
    _startedAtTimelineUs = _timelineClock();
    _captureId += 1;
    _startedAtUtc = _clock().toUtc();
    _endedAtUtc = null;
    _stopReason = null;
    _recording = true;
    _elapsed
      ..reset()
      ..start();
    _attachFrameTimings();
    _durationTimer = Timer(
      maximumDuration,
      () => _stop(TopicScrollCaptureStopReason.durationLimit),
    );
    notifySafely();
  }

  void stop() => _stop(TopicScrollCaptureStopReason.manual);

  void clear() {
    if (_disposed) return;
    if (_recording) _stop(TopicScrollCaptureStopReason.manual, notify: false);
    _events.clear();
    _startedAtUtc = null;
    _endedAtUtc = null;
    _stopReason = null;
    _sequence = 0;
    _topicEventCount = 0;
    _frameCount = 0;
    _slowBuildFrameCount = 0;
    _slowRasterFrameCount = 0;
    _maximumBuildMicroseconds = 0;
    _maximumRasterMicroseconds = 0;
    _maximumTotalSpanMicroseconds = 0;
    notifySafely();
  }

  void recordTopicEvent(String name, Map<String, Object?> data) {
    if (!_recording) return;
    try {
      _topicEventCount += 1;
      _append(category: 'topic', name: name, data: data);
    } on Object {
      // Capture is observational. A malformed field must not touch the view.
    }
  }

  /// The small envelope is captured on the caller. Traversing all events,
  /// scrubbing strings, normalizing values, and encoding JSON happen only on
  /// export, in a background isolate after the reproduction is over.
  Future<String> buildJsonReport() => _buildReport(compact: false);

  /// A bounded text report suitable for pasting into an issue or conversation.
  Future<String> buildPerformanceReport() => _buildReport(compact: true);

  Future<String> _buildReport({required bool compact}) {
    final snapshot = state;
    final report = <String, Object?>{
      'version': reportFormatVersion,
      'kind': 'topic-scroll-capture',
      'generatedAtUtc': _clock().toUtc().toIso8601String(),
      'app': {
        'version': AppRelease.version,
        'buildChannel': AppRelease.buildChannel,
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        'platform': defaultTargetPlatform.name,
      },
      'capture': {
        'status': snapshot.isRecording ? 'recording' : 'stopped',
        if (snapshot.startedAtUtc != null)
          'startedAtUtc': snapshot.startedAtUtc!.toIso8601String(),
        if (snapshot.endedAtUtc != null)
          'endedAtUtc': snapshot.endedAtUtc!.toIso8601String(),
        if (snapshot.duration != null)
          'durationUs': snapshot.duration!.inMicroseconds,
        if (snapshot.stopReason != null)
          'stopReason': snapshot.stopReason!.name,
        'memoryOnly': true,
        'maximumEvents': maximumEvents,
        'maximumDurationMs': maximumDuration.inMilliseconds,
      },
      'scope': {
        'captured': [
          'topic scroll and metrics notifications',
          'SuperListView sliver layout and visible ranges',
          'visible post geometry and row attachment lifecycle',
          'topic window, paging, and extent invalidation decisions',
          'viewport anchor capture and correction decisions',
          'Flutter UI-thread build and raster frame timings',
          'post layout and viewport bookkeeping durations',
        ],
        'excluded': [
          'post bodies and titles',
          'site URLs and credentials',
          'native compositor and operating-system traces',
        ],
      },
      'summary': {
        'eventCount': snapshot.eventCount,
        'topicEventCount': snapshot.topicEventCount,
        'frameCount': snapshot.frameCount,
        'slowBuildFrameCount': snapshot.slowBuildFrameCount,
        'slowRasterFrameCount': snapshot.slowRasterFrameCount,
        'displayRefreshRate': snapshot.displayRefreshRate,
        'slowFrameThresholdUs': snapshot.frameBudgetMicroseconds,
        'maximumBuildUs': _maximumBuildMicroseconds,
        'maximumRasterUs': _maximumRasterMicroseconds,
        'maximumTotalSpanUs': _maximumTotalSpanMicroseconds,
      },
      'events': [for (final event in _events) event.toJson()],
    };
    return Isolate.run(() => encodeTopicScrollReport(report, compact: compact));
  }

  void _append({
    required String category,
    required String name,
    required Map<String, Object?> data,
  }) {
    if (!_recording) return;
    _events.add(
      TopicScrollCaptureEvent(
        sequence: ++_sequence,
        elapsedMicroseconds: _elapsed.elapsedMicroseconds,
        category: category,
        name: name,
        frameNumber: category == 'topic' ? _currentFrameNumber() : null,
        // Producers hand the recorder fresh maps of primitive values. Keep
        // this shallow on the hot path; deep copying, redaction, and JSON
        // normalization are intentionally deferred until export.
        data: Map.unmodifiable(data),
      ),
    );
    if (_events.length >= maximumEvents) {
      _stop(TopicScrollCaptureStopReason.eventLimit);
    }
  }

  void _attachFrameTimings() {
    try {
      SchedulerBinding.instance.addTimingsCallback(_recordFrameTimings);
      _timingsAttached = true;
    } on Object {
      // A headless test can use topic event capture without a scheduler.
      _timingsAttached = false;
    }
  }

  void _detachFrameTimings() {
    if (!_timingsAttached) return;
    _timingsAttached = false;
    try {
      SchedulerBinding.instance.removeTimingsCallback(_recordFrameTimings);
    } on Object {
      // The binding may already be shutting down with the app.
    }
  }

  void _recordFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      if (!_recording) return;
      final vsyncUs = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      // The engine delivers timings in batches. Do not count frames that
      // started before the user armed this recording.
      if (vsyncUs < _startedAtTimelineUs) continue;
      final buildUs = timing.buildDuration.inMicroseconds;
      final rasterUs = timing.rasterDuration.inMicroseconds;
      final totalUs = timing.totalSpan.inMicroseconds;
      _frameCount += 1;
      if (buildUs > _frameBudgetUs) {
        _slowBuildFrameCount += 1;
      }
      if (rasterUs > _frameBudgetUs) {
        _slowRasterFrameCount += 1;
      }
      _maximumBuildMicroseconds = _maximumBuildMicroseconds > buildUs
          ? _maximumBuildMicroseconds
          : buildUs;
      _maximumRasterMicroseconds = _maximumRasterMicroseconds > rasterUs
          ? _maximumRasterMicroseconds
          : rasterUs;
      _maximumTotalSpanMicroseconds = _maximumTotalSpanMicroseconds > totalUs
          ? _maximumTotalSpanMicroseconds
          : totalUs;
      _append(
        category: 'frame',
        name: 'frame.timing',
        data: {
          if (timing.frameNumber >= 0) 'frameNumber': timing.frameNumber,
          'vsyncStartUs': vsyncUs,
          'buildUs': buildUs,
          'rasterUs': rasterUs,
          'vsyncOverheadUs': timing.vsyncOverhead.inMicroseconds,
          'totalSpanUs': totalUs,
          'layerCacheCount': timing.layerCacheCount,
          'layerCacheBytes': timing.layerCacheBytes,
          'pictureCacheCount': timing.pictureCacheCount,
          'pictureCacheBytes': timing.pictureCacheBytes,
        },
      );
    }
  }

  void _stop(TopicScrollCaptureStopReason reason, {bool notify = true}) {
    if (!_recording) return;
    _recording = false;
    _elapsed.stop();
    _endedAtUtc = _clock().toUtc();
    _stopReason = reason;
    _durationTimer?.cancel();
    _durationTimer = null;
    _detachFrameTimings();
    if (notify && !_disposed) notifySafely();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stop(TopicScrollCaptureStopReason.manual, notify: false);
    _durationTimer?.cancel();
    _durationTimer = null;
    _detachFrameTimings();
    super.dispose();
  }
}

int? _readCurrentFrameNumber() {
  try {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle) return null;
    final number = scheduler.platformDispatcher.frameData.frameNumber;
    return number >= 0 ? number : null;
  } on Object {
    return null;
  }
}

DateTime _utcNow() => DateTime.now().toUtc();
