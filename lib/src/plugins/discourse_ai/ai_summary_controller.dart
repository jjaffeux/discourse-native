// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/shell_extensions.dart';
import 'ai_summary.dart';
import 'ai_summary_api.dart';

/// Coordinates cached and newly streamed Discourse AI topic summaries.
final class AiSummaryController {
  const AiSummaryController({
    required this.api,
    required PluginRequestHost requests,
    required PluginChannelReader channelsFor,
    this.streamTimeout = const Duration(minutes: 3),
  }) : _requests = requests,
       _channelsFor = channelsFor;

  final AiSummaryApi api;
  final PluginRequestHost _requests;
  final PluginChannelReader _channelsFor;
  final Duration streamTimeout;

  Future<AiTopicSummary> load({
    required String siteUrl,
    required int topicId,
    required bool hasCachedSummary,
    bool regenerate = false,
  }) async {
    final lease = _requests.capture(siteUrl);
    final credentials = await _requests.credentialsFor(siteUrl);
    _requireCurrent(lease);

    if (hasCachedSummary && !regenerate) {
      final summary = await api.cached(
        siteUrl: siteUrl,
        topicId: topicId,
        apiKey: credentials.apiKey,
        clientId: credentials.clientId,
      );
      _requireCurrent(lease);
      return summary;
    }
    final apiKey = credentials.apiKey;
    if (apiKey == null) {
      throw StateError('Sign in to generate this summary.');
    }

    final channels = _channelsFor(siteUrl);
    if (channels == null) {
      final body = await api.generate(
        siteUrl: siteUrl,
        topicId: topicId,
        apiKey: apiKey,
        clientId: credentials.clientId,
        stream: false,
        regenerate: regenerate,
      );
      _requireCurrent(lease);
      return AiTopicSummary.fromJson(body) ??
          (throw const FormatException('Summary response had no summary.'));
    }

    final completed = Completer<AiTopicSummary>();
    final subscription = channels.subscribe(
      '/discourse-ai/summaries/topic/$topicId',
      (data, _) {
        if (!lease.isCurrent) return;
        if (data is! Map<String, dynamic>) return;
        final body = data;
        final summary = AiTopicSummary.fromJson(body);
        if (body['done'] == true && summary != null && !completed.isCompleted) {
          completed.complete(summary);
        }
      },
    );
    try {
      final response = await api.generate(
        siteUrl: siteUrl,
        topicId: topicId,
        apiKey: apiKey,
        clientId: credentials.clientId,
        regenerate: regenerate,
      );
      _requireCurrent(lease);
      if (AiTopicSummary.fromJson(response) case final cached?) return cached;
      final summary = await completed.future.timeout(streamTimeout);
      _requireCurrent(lease);
      return summary;
    } finally {
      subscription.cancel();
    }
  }

  static void _requireCurrent(PluginSiteLease lease) {
    if (!lease.isCurrent) {
      throw StateError('The forum session changed while loading its summary.');
    }
  }
}
