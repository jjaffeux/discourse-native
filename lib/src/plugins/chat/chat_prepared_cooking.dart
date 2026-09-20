// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:discourse_cooking/discourse_cooking.dart';

import '../../plugin_api/cooking_plugin.dart';
import 'chat_cooking_coordinator.dart';

/// Owns bounded, site-aware prepared drafts and urgent submission cooking.
///
/// Context and snapshots are assembled only after scheduler admission. The
/// caller owns message authority and revision checks for submissions. This
/// object owns the supplied `scheduler`, including its synchronous disposal.
final class ChatPreparedCooking {
  ChatPreparedCooking({
    required PluginCookingHost host,
    required CookingContext Function(String siteUrl) contextFor,
    ChatCookingCoordinator? scheduler,
    this.maxDrafts = 32,
    this.maxReadyBytes = 2 * 1024 * 1024,
    this.maxSubmissions = 32,
  }) : _host = host,
       _contextFor = contextFor,
       _scheduler = scheduler ?? ChatCookingCoordinator(cook: host.cook) {
    if (maxDrafts < 1) throw ArgumentError.value(maxDrafts, 'maxDrafts');
    if (maxReadyBytes < 1) {
      throw ArgumentError.value(maxReadyBytes, 'maxReadyBytes');
    }
    if (maxSubmissions < 1) {
      throw ArgumentError.value(maxSubmissions, 'maxSubmissions');
    }
  }

  final PluginCookingHost _host;
  final CookingContext Function(String siteUrl) _contextFor;
  final ChatCookingCoordinator _scheduler;
  final int maxDrafts, maxReadyBytes, maxSubmissions;
  final _drafts = <Object, _PreparedDraft>{};
  final _submissions = <Object, _Submission>{};
  int _readyBytes = 0;
  bool _disposed = false;

  /// Keeps the latest source for [key], coalescing repeated document listeners.
  ///
  /// [contextBuilder] takes precedence over a static [context] and the default
  /// site context. It runs after debounce, including on context notifications.
  /// Replacing only the closure does not itself restart unchanged source; call
  /// [refreshSite] when facts outside the host's watched context change.
  void prepare({
    required Object key,
    required String siteUrl,
    required String raw,
    CookingContext? context,
    CookingContext Function()? contextBuilder,
  }) {
    if (_disposed) return;
    final held = _drafts[key];
    if (held != null &&
        held.siteUrl == siteUrl &&
        held.raw == raw &&
        _sameContext(held.context, context)) {
      held.contextBuilder = contextBuilder;
      _touch(held);
      if (held.suspended) {
        held.suspended = false;
        if (held.html == null ||
            held.request == null ||
            !_requestIsCurrent(held.request!)) {
          _scheduleDraft(held);
        }
      }
      return;
    }
    if (held != null) _removeDraft(held);
    while (_drafts.length >= maxDrafts) {
      _removeDraft(_drafts.values.first);
    }
    final draft = _PreparedDraft(
      key: key,
      siteUrl: siteUrl,
      raw: raw,
      context: context,
      contextBuilder: contextBuilder,
    );
    _drafts[key] = draft;
    try {
      final stop = _host.watch(
        siteUrl: siteUrl,
        raw: raw,
        onChanged: () {
          if (_ownsDraft(draft)) _scheduleDraft(draft);
        },
      );
      if (!_ownsDraft(draft)) {
        _stopWatching(stop);
        return;
      }
      draft.stopWatching = stop;
    } catch (_) {
      if (_ownsDraft(draft)) _removeDraft(draft);
      return;
    }
    _scheduleDraft(draft);
  }

  /// Returns only an exact, still-current prepared document without consuming
  /// it. A later composer clear explicitly cancels ownership through [cancel].
  String? takeReady({required Object key, required String raw}) {
    final draft = _drafts[key];
    if (_disposed || draft == null || draft.raw != raw) return null;
    _touch(draft);
    final request = draft.request;
    if (draft.html == null || request == null) return null;
    if (!_requestIsCurrent(request)) {
      _scheduleDraft(draft);
      return null;
    }
    return _ownsDraft(draft) ? draft.html : null;
  }

  /// Starts urgent work on a microtask, independently of staging or sending.
  /// No snapshot is rebuilt to check freshness: the original host request is
  /// passed to cooking and rechecked at completion.
  Future<String?> cook({
    required Object key,
    required String siteUrl,
    required String raw,
    CookingContext? context,
    CookingContext Function()? contextBuilder,
    required bool Function() isCurrent,
  }) {
    if (_disposed) return Future.value();
    final held = _submissions.remove(key);
    if (held != null) _scheduler.cancel(held.schedulerKey);
    if (_submissions.length >= maxSubmissions) return Future.value();
    final submission = _Submission(key: key, siteUrl: siteUrl);
    _submissions[key] = submission;
    CookingRequest? request;

    bool current() {
      if (!_ownsSubmission(submission)) return false;
      try {
        return isCurrent() &&
            _ownsSubmission(submission) &&
            (request == null || _requestIsCurrent(request!)) &&
            _ownsSubmission(submission);
      } catch (_) {
        return false;
      }
    }

    return _scheduler
        .schedule(
          key: submission.schedulerKey,
          siteUrl: siteUrl,
          urgent: true,
          isCurrent: current,
          buildRequest: () => request = _host.request(
            siteUrl: siteUrl,
            raw: raw,
            profile: CookingProfile.chat,
            context: contextBuilder?.call() ?? context ?? _contextFor(siteUrl),
          ),
        )
        .then<String?>((result) {
          if (result == null || result.isFallback || !current()) return null;
          return result.html;
        }, onError: (Object _, StackTrace _) => null)
        .whenComplete(() {
          if (identical(_submissions[key], submission)) {
            _submissions.remove(key);
          }
        });
  }

  void cancel(Object key) {
    final draft = _drafts[key];
    if (draft != null) _removeDraft(draft);
    final submission = _submissions.remove(key);
    if (submission != null) _scheduler.cancel(submission.schedulerKey);
  }

  /// Stops hidden-draft work while retaining its source and current ready HTML.
  /// Watched changes still invalidate ready output, but do not schedule a cook
  /// until the next [prepare]. Submission work has separate ownership.
  void suspend(Object key) {
    final draft = _drafts[key];
    if (_disposed || draft == null) return;
    draft.suspended = true;
    draft.run = Object();
    _scheduler.cancel(draft.schedulerKey);
  }

  void forget(String siteUrl) {
    final drafts = _drafts.values
        .where((draft) => draft.siteUrl == siteUrl)
        .toList(growable: false);
    for (final draft in drafts) {
      _removeDraft(draft);
    }
    _submissions.removeWhere((_, submission) => submission.siteUrl == siteUrl);
    _scheduler.forget(siteUrl);
  }

  void refreshSite(String siteUrl) {
    if (_disposed) return;
    final drafts = _drafts.values
        .where((draft) => draft.siteUrl == siteUrl)
        .toList(growable: false);
    for (final draft in drafts) {
      if (_ownsDraft(draft)) _scheduleDraft(draft);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final draft in _drafts.values.toList(growable: false)) {
      _removeDraft(draft);
    }
    _submissions.clear();
    _scheduler.dispose();
  }

  void _scheduleDraft(_PreparedDraft draft) {
    if (!_ownsDraft(draft)) return;
    _clearReady(draft);
    final run = Object();
    draft.run = run;
    if (draft.suspended) {
      _scheduler.cancel(draft.schedulerKey);
      return;
    }
    CookingRequest? request;
    bool current() =>
        _ownsDraft(draft) &&
        !draft.suspended &&
        identical(draft.run, run) &&
        (request == null || _requestIsCurrent(request!)) &&
        _ownsDraft(draft) &&
        !draft.suspended &&
        identical(draft.run, run);
    unawaited(
      _scheduler
          .schedule(
            key: draft.schedulerKey,
            siteUrl: draft.siteUrl,
            isCurrent: current,
            buildRequest: () => request = _host.request(
              siteUrl: draft.siteUrl,
              raw: draft.raw,
              profile: CookingProfile.chat,
              context:
                  draft.contextBuilder?.call() ??
                  draft.context ??
                  _contextFor(draft.siteUrl),
            ),
          )
          .then<void>((result) {
            if (result == null ||
                result.isFallback ||
                request == null ||
                !current()) {
              return;
            }
            _keepReady(draft, request!, result.html);
          }, onError: (Object _, StackTrace _) {}),
    );
  }

  bool _requestIsCurrent(CookingRequest request) {
    try {
      return _host.isCurrent(request);
    } catch (_) {
      return false;
    }
  }

  bool _ownsDraft(_PreparedDraft draft) =>
      !_disposed && identical(_drafts[draft.key], draft);

  bool _ownsSubmission(_Submission submission) =>
      !_disposed && identical(_submissions[submission.key], submission);

  void _touch(_PreparedDraft draft) {
    _drafts.remove(draft.key);
    _drafts[draft.key] = draft;
  }

  void _keepReady(_PreparedDraft draft, CookingRequest request, String html) {
    if (html.length > maxReadyBytes) return;
    final bytes = utf8.encode(html).length;
    if (bytes > maxReadyBytes) return;
    for (final candidate in _drafts.values) {
      if (_readyBytes + bytes <= maxReadyBytes) break;
      _clearReady(candidate);
    }
    draft.request = request;
    draft.html = html;
    draft.bytes = bytes;
    _readyBytes += bytes;
  }

  void _clearReady(_PreparedDraft draft) {
    _readyBytes -= draft.bytes;
    draft.bytes = 0;
    draft.request = null;
    draft.html = null;
  }

  void _removeDraft(_PreparedDraft draft) {
    _drafts.remove(draft.key);
    _scheduler.cancel(draft.schedulerKey);
    _clearReady(draft);
    final stop = draft.stopWatching;
    draft.stopWatching = null;
    if (stop != null) _stopWatching(stop);
  }

  void _stopWatching(void Function() stop) {
    try {
      stop();
    } catch (_) {
      // Local ownership is already retired, even if an observer misbehaves.
    }
  }

  static bool _sameContext(CookingContext? a, CookingContext? b) =>
      identical(a, b) ||
      a != null &&
          b != null &&
          jsonEncode(a.toJson()) == jsonEncode(b.toJson());
}

final class _PreparedDraft {
  _PreparedDraft({
    required this.key,
    required this.siteUrl,
    required this.raw,
    required this.context,
    required this.contextBuilder,
  });

  final Object key;
  final String siteUrl, raw;
  final CookingContext? context;
  CookingContext Function()? contextBuilder;
  final schedulerKey = Object();
  Object? run;
  void Function()? stopWatching;
  CookingRequest? request;
  String? html;
  int bytes = 0;
  bool suspended = false;
}

final class _Submission {
  _Submission({required this.key, required this.siteUrl});
  final Object key;
  final String siteUrl;
  final schedulerKey = Object();
}
