import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';

const aiSummaryAvailabilityDataKey = PluginDataKey<AiSummaryAvailability>(
  owner: 'discourse-ai',
  name: 'topic-summary-availability',
);

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
    final text = summary['summarized_text'];
    if (text is! String || text.trim().isEmpty) return null;
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

/// A generation the stream job could not finish. The job publishes this on the
/// summary channel in place of the summary, after the POST that enqueued it
/// has already answered success, so it is the only thing that can end the
/// wait before the stream deadline.
@immutable
final class AiSummaryStreamFailure implements Exception {
  const AiSummaryStreamFailure({this.type, this.resetTime});

  static const creditLimitExceededType = 'credit_limit_exceeded';

  /// Null for anything that does not report an error, including a bare
  /// `{"done": true}`.
  static AiSummaryStreamFailure? fromJson(Map<String, dynamic> json) {
    final type = jsonText(json['error_type']);
    if (json['error'] != true && type == null) return null;
    final details = jsonObject(json['details']);
    return AiSummaryStreamFailure(
      type: type,
      // Upstream prefers the formatted reset moment over the distance to it;
      // the site sends both blank when the allocation has no next reset.
      resetTime:
          jsonText(details['reset_time_absolute']) ??
          jsonText(details['reset_time_relative']),
    );
  }

  final String? type;

  /// Human-readable, already formatted by the site.
  final String? resetTime;

  bool get creditLimitExceeded => type == creditLimitExceededType;

  @override
  String toString() => appL10n.aiSummaryStreamFailureType((type).toString());
}
