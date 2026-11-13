import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'discourse_ai_icons.dart';

const discourseAiRelatedTopicRecommendationSourceId =
    TopicRecommendationSourceId('discourse-ai/related');

TopicRecommendationSourceDefinition
get discourseAiRelatedTopicRecommendationSource =>
    TopicRecommendationSourceDefinition(
      id: discourseAiRelatedTopicRecommendationSourceId,
      label: appL10n.related,
      icon: DiscourseAiIcons.sparkles,
    );

const discourseAiRelatedTopicRecommendationSourceCodec =
    DiscourseAiRelatedTopicRecommendationSourceCodec();

final class DiscourseAiRelatedTopicRecommendationSourceCodec
    extends TopicRecommendationSourceCodec {
  const DiscourseAiRelatedTopicRecommendationSourceCodec();

  @override
  TopicRecommendationSourceDefinition get definition =>
      discourseAiRelatedTopicRecommendationSource;

  @override
  Set<String> get legacyStoredIds => const {'related'};

  @override
  List<Map<String, dynamic>>? decodeTopicRows(Map<String, dynamic> json) {
    if (!json.containsKey('related_topics')) return null;
    return List.unmodifiable(jsonObjects(json['related_topics']));
  }
}
