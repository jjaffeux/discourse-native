import 'dart:async';

import '../../data/api_credentials.dart';
import '../../data/site_lifecycle.dart';
import '../../plugin_api/live_channels.dart';
import 'ai_summary.dart';
import 'ai_summary_api.dart';

typedef AiSummaryTrackerReader =
    PluginLiveChannelHandle? Function(String siteUrl);

/// Coordinates cached and newly streamed Discourse AI topic summaries.
final class AiSummaryController {
  const AiSummaryController({
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.trackerFor,
    this.streamTimeout = const Duration(minutes: 3),
  });

  final AiSummaryApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final AiSummaryTrackerReader trackerFor;
  final Duration streamTimeout;

  Future<AiTopicSummary> load({
    required String siteUrl,
    required int topicId,
    required bool hasCachedSummary,
    bool regenerate = false,
  }) async {
    final lease = lifecycle.capture(siteUrl);
    final apiKey = await credentials.apiKeyFor(siteUrl);
    if (!lease.isCurrent) {
      throw StateError('The forum session changed while loading its summary.');
    }

    if (hasCachedSummary && !regenerate) {
      return api.cached(siteUrl: siteUrl, topicId: topicId, apiKey: apiKey);
    }
    if (apiKey == null) {
      throw StateError('Sign in to generate this summary.');
    }

    final tracker = trackerFor(siteUrl);
    if (tracker == null) {
      final body = await api.generate(
        siteUrl: siteUrl,
        topicId: topicId,
        apiKey: apiKey,
        stream: false,
        regenerate: regenerate,
      );
      return AiTopicSummary.fromJson(body) ??
          (throw const FormatException('Summary response had no summary.'));
    }

    final completed = Completer<AiTopicSummary>();
    final subscription = tracker.subscribe(
      '/discourse-ai/summaries/topic/$topicId',
      (data, _) {
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
        regenerate: regenerate,
      );
      if (AiTopicSummary.fromJson(response) case final cached?) return cached;
      return await completed.future.timeout(streamTimeout);
    } finally {
      subscription.cancel();
    }
  }
}
