// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_cooking/discourse_cooking.dart';

/// Coalesces draft revisions before assembling their immutable cooking context.
///
/// One physical cook and at most [maxQueuedJobs] pending jobs are retained.
/// Superseding an active job settles its consumer immediately, but keeps that
/// physical slot occupied until the worker finishes. Urgent sends and edits
/// bypass the draft debounce and run before queued drafts.
final class ChatCookingCoordinator {
  ChatCookingCoordinator({
    required Future<CookingResult> Function(CookingRequest) cook,
    this.draftDebounce = const Duration(milliseconds: 40),
    this.maxQueuedJobs = 16,
    Timer Function(Duration, void Function()) timerFactory = Timer.new,
  }) : _cook = cook,
       _timerFactory = timerFactory {
    if (draftDebounce.isNegative) {
      throw ArgumentError.value(draftDebounce, 'draftDebounce');
    }
    if (maxQueuedJobs < 1) {
      throw ArgumentError.value(maxQueuedJobs, 'maxQueuedJobs');
    }
  }

  final Future<CookingResult> Function(CookingRequest) _cook;
  final Timer Function(Duration, void Function()) _timerFactory;
  final Duration draftDebounce;
  final int maxQueuedJobs;
  final _queued = <Object, _CookingJob>{};
  _CookingJob? _active;
  bool _drainScheduled = false;
  bool _disposed = false;

  /// Replaces work with the same globally scoped [key]. Neither request
  /// construction nor cooking runs synchronously in this method.
  ///
  /// The caller owns source, account, context and revision checks through
  /// [isCurrent], and retains readable raw content when the result is null.
  /// Exceptions also resolve to null. At capacity, the oldest queued draft is
  /// displaced; when every queued job is urgent, the new job is declined.
  Future<CookingResult?> schedule({
    required Object key,
    required String siteUrl,
    required CookingRequest Function() buildRequest,
    required bool Function() isCurrent,
    bool urgent = false,
  }) {
    if (_disposed) return Future.value();
    cancel(key);
    if (_queued.length >= maxQueuedJobs) {
      _CookingJob? displaced;
      for (final job in _queued.values) {
        if (!job.urgent) {
          displaced = job;
          break;
        }
      }
      if (displaced == null) return Future.value();
      _queued.remove(displaced.key);
      displaced.complete(null);
    }

    final job = _CookingJob(
      key: key,
      siteUrl: siteUrl,
      buildRequest: buildRequest,
      isCurrent: isCurrent,
      urgent: urgent,
      ready: urgent || draftDebounce == Duration.zero,
    );
    _queued[key] = job;
    if (!job.ready) {
      try {
        job.timer = _timerFactory(draftDebounce, () {
          if (_disposed || !identical(_queued[key], job)) return;
          job.ready = true;
          _scheduleDrain();
        });
        if (_disposed || !identical(_queued[key], job)) job.timer?.cancel();
      } catch (_) {
        if (identical(_queued[key], job)) _queued.remove(key);
        job.complete(null);
      }
    }
    _scheduleDrain();
    return job.result.future;
  }

  void cancel(Object key) {
    _queued.remove(key)?.complete(null);
    if (_active case final active? when active.key == key) {
      active.complete(null);
    }
  }

  void forget(String siteUrl) {
    final removed = _queued.values
        .where((job) => job.siteUrl == siteUrl)
        .toList(growable: false);
    for (final job in removed) {
      _queued.remove(job.key);
      job.complete(null);
    }
    if (_active case final active? when active.siteUrl == siteUrl) {
      active.complete(null);
    }
  }

  /// Cancels debounce timers and settles consumers without awaiting the worker.
  /// The already running future remains observed until it finishes.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final job in _queued.values) {
      job.complete(null);
    }
    _queued.clear();
    _active?.complete(null);
  }

  void _scheduleDrain() {
    if (_disposed || _drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(() {
      _drainScheduled = false;
      if (_disposed || _active != null) return;
      _CookingJob? selected;
      for (final job in _queued.values) {
        if (!job.ready) continue;
        selected ??= job;
        if (job.urgent) {
          selected = job;
          break;
        }
      }
      if (selected == null) return;
      _queued.remove(selected.key);
      selected.timer?.cancel();
      _active = selected;
      unawaited(_run(selected));
    });
  }

  bool _isCurrent(_CookingJob job) {
    if (_disposed || job.result.isCompleted || !identical(_active, job)) {
      return false;
    }
    final current = job.isCurrent();
    // The injected callback can synchronously cancel or supersede this job.
    return current &&
        !_disposed &&
        !job.result.isCompleted &&
        identical(_active, job);
  }

  Future<void> _run(_CookingJob job) async {
    try {
      if (!_isCurrent(job)) {
        job.complete(null);
        return;
      }
      final request = job.buildRequest();
      if (!_isCurrent(job)) {
        job.complete(null);
        return;
      }
      final result = await _cook(request);
      job.complete(_isCurrent(job) ? result : null);
    } catch (_) {
      job.complete(null);
    } finally {
      if (identical(_active, job)) _active = null;
      if (_queued.isNotEmpty) _scheduleDrain();
    }
  }
}

final class _CookingJob {
  _CookingJob({
    required this.key,
    required this.siteUrl,
    required this.buildRequest,
    required this.isCurrent,
    required this.urgent,
    required this.ready,
  });

  final Object key;
  final String siteUrl;
  final CookingRequest Function() buildRequest;
  final bool Function() isCurrent;
  final bool urgent;
  final result = Completer<CookingResult?>();
  bool ready;
  Timer? timer;

  void complete(CookingResult? value) {
    timer?.cancel();
    if (!result.isCompleted) result.complete(value);
  }
}
