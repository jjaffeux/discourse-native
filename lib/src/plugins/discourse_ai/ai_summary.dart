import 'package:flutter/foundation.dart';

import '../../models/json.dart';
import '../../plugin_api/plugin_data.dart';

const aiSummaryAvailabilityDataKey = PluginDataKey<AiSummaryAvailability>(
  owner: 'discourse-ai',
  name: 'topic-summary-availability',
);

/// The guardian-scoped Discourse AI fields on a full topic serializer.
@immutable
class AiSummaryAvailability {
  const AiSummaryAvailability({
    required this.summarizable,
    required this.hasCachedSummary,
  });

  static AiSummaryAvailability? fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('summarizable') &&
        !json.containsKey('has_cached_summary')) {
      return null;
    }
    return AiSummaryAvailability(
      summarizable: json['summarizable'] == true,
      hasCachedSummary: json['has_cached_summary'] == true,
    );
  }

  final bool summarizable;
  final bool hasCachedSummary;

  @override
  bool operator ==(Object other) =>
      other is AiSummaryAvailability &&
      other.summarizable == summarizable &&
      other.hasCachedSummary == hasCachedSummary;

  @override
  int get hashCode => Object.hash(summarizable, hasCachedSummary);
}

/// One generated topic summary, whether returned by HTTP or message bus.
@immutable
class AiTopicSummary {
  const AiTopicSummary({
    required this.text,
    this.algorithm,
    this.updatedAt,
    this.outdated = false,
    this.canRegenerate = false,
    this.newPostsSinceSummary = 0,
  });

  static AiTopicSummary? fromJson(Map<String, dynamic> json) {
    final summary = jsonObject(json['ai_topic_summary']);
    final text = jsonText(summary['summarized_text']);
    if (text == null) return null;
    return AiTopicSummary(
      text: text,
      algorithm: jsonText(summary['algorithm']),
      updatedAt: jsonDate(summary['updated_at']),
      outdated: summary['outdated'] == true,
      canRegenerate: summary['can_regenerate'] == true,
      newPostsSinceSummary: jsonInt(summary['new_posts_since_summary']),
    );
  }

  final String text;
  final String? algorithm;
  final DateTime? updatedAt;
  final bool outdated;
  final bool canRegenerate;
  final int newPostsSinceSummary;

  @override
  bool operator ==(Object other) =>
      other is AiTopicSummary &&
      other.text == text &&
      other.algorithm == algorithm &&
      other.updatedAt == updatedAt &&
      other.outdated == outdated &&
      other.canRegenerate == canRegenerate &&
      other.newPostsSinceSummary == newPostsSinceSummary;

  @override
  int get hashCode => Object.hash(
    text,
    algorithm,
    updatedAt,
    outdated,
    canRegenerate,
    newPostsSinceSummary,
  );
}
