// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/live_channels.dart';
import 'ai_summary.dart';
import 'ai_summary_api.dart';

final class AiSummaryController {
  AiSummaryController({
    required this.api,
    required PluginRequestHost requests,
    required PluginTrackerReader trackerFor,
    this.streamTimeout = const Duration(minutes: 3),
  }) : _requests = requests,
       _trackerFor = trackerFor;

  final AiSummaryApi api;
  final PluginRequestHost _requests;
  final PluginTrackerReader _trackerFor;
  final Duration streamTimeout;
  final Map<AiSummaryRequest, String> _pending = {};
  bool _disposed = false;

  AiSummaryRequest load({
    required String siteUrl,
    required int topicId,
    required bool hasCachedSummary,
    bool regenerate = false,
  }) {
    final request = AiSummaryRequest._(
      _requests.capture(siteUrl),
      _pending.remove,
    );
    _pending[request] = siteUrl;
    if (_disposed) {
      request.cancel();
    } else {
      unawaited(_load(request, siteUrl, topicId, hasCachedSummary, regenerate));
    }
    return request;
  }

  void forget(String siteUrl) {
    for (final entry in _pending.entries.toList()) {
      if (entry.value == siteUrl) entry.key._sessionChanged();
    }
  }

  void dispose() {
    _disposed = true;
    for (final request in _pending.keys.toList()) {
      request.cancel();
    }
  }

  Future<void> _load(
    AiSummaryRequest request,
    String siteUrl,
    int topicId,
    bool hasCachedSummary,
    bool regenerate,
  ) async {
    try {
      if (!request._checkCurrent()) return;
      final credentials = await _requests.credentialsFor(siteUrl);
      if (!request._checkCurrent()) return;

      if (hasCachedSummary && !regenerate) {
        final summary = await api.cached(
          siteUrl: siteUrl,
          topicId: topicId,
          apiKey: credentials.apiKey,
          clientId: credentials.clientId,
        );
        if (request._checkCurrent()) request._complete(summary);
        return;
      }
      final apiKey = credentials.apiKey;
      if (apiKey == null) {
        throw StateError('Sign in to generate this summary.');
      }

      final tracker = _trackerFor(siteUrl);
      if (tracker != null) {
        request._subscribe(tracker, topicId);
        if (!request._checkCurrent()) return;
      }
      final response = await api.generate(
        siteUrl: siteUrl,
        topicId: topicId,
        apiKey: apiKey,
        clientId: credentials.clientId,
        stream: tracker != null,
        regenerate: regenerate,
      );
      if (!request._checkCurrent()) return;
      if (AiTopicSummary.fromJson(response) case final summary?) {
        request._complete(summary);
      } else if (tracker == null) {
        throw const FormatException('Summary response had no summary.');
      } else {
        request._waitForStream(streamTimeout);
      }
    } catch (error, stack) {
      // The transport cannot abort a sent request. Keep observing its errors
      // even after the dialog has cancelled and released its live resources.
      request._fail(error, stack);
    }
  }
}

/// One summary load, owned by the dialog until completion or dismissal.
final class AiSummaryRequest {
  AiSummaryRequest._(this._lease, this._onSettled);

  final PluginSiteLease _lease;
  void Function(AiSummaryRequest)? _onSettled;
  final _result = Completer<AiTopicSummary>();
  PluginLiveChannelSubscription? _subscription;
  Timer? _deadline;
  AiTopicSummary? _streamedSummary;
  bool _waitingForStream = false;

  Future<AiTopicSummary> get result => _result.future;

  void cancel() => _fail(const AiSummaryCancelled());

  bool _checkCurrent() {
    if (_result.isCompleted) return false;
    if (!_lease.isCurrent) {
      _sessionChanged();
      return false;
    }
    return true;
  }

  void _sessionChanged() =>
      _fail(StateError('The forum session changed while loading its summary.'));

  void _subscribe(PluginLiveChannelHandle tracker, int topicId) {
    final subscription = tracker.subscribe(
      '/discourse-ai/summaries/topic/$topicId',
      (data, _) {
        if (!_checkCurrent() || data is! Map<String, dynamic>) return;
        final summary = AiTopicSummary.fromJson(data);
        if (data['done'] != true || summary == null) return;
        // A completed stream can arrive before the generation POST returns.
        _streamedSummary ??= summary;
        if (_waitingForStream) _complete(_streamedSummary!);
      },
    );
    if (_result.isCompleted) {
      subscription.cancel();
    } else {
      _subscription = subscription;
    }
  }

  void _waitForStream(Duration timeout) {
    if (_streamedSummary case final summary?) {
      _complete(summary);
      return;
    }
    _waitingForStream = true;
    _deadline = Timer(timeout, () {
      if (_checkCurrent()) {
        _fail(TimeoutException('Summary stream timed out.', timeout));
      }
    });
  }

  void _complete(AiTopicSummary summary) {
    if (_result.isCompleted) return;
    _result.complete(summary);
    _release();
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_result.isCompleted) return;
    _result.completeError(error, stack);
    _release();
  }

  void _release() {
    _subscription?.cancel();
    _subscription = null;
    _deadline?.cancel();
    _deadline = null;
    _streamedSummary = null;
    _onSettled?.call(this);
    _onSettled = null;
  }
}

final class AiSummaryCancelled implements Exception {
  const AiSummaryCancelled();
}
