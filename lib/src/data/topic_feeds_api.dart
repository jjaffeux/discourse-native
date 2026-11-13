import '../models/topic.dart';

abstract interface class TopicFeedsApi {
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  });

  Future<List<int>> dismissNewTopics({
    required String siteUrl,
    required String apiKey,
    required bool dismissTopics,
    required bool dismissPosts,
    bool tracked = false,
    int? categoryId,
    String? tagName,
    List<int>? topicIds,
    String? clientId,
  });

  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  });
}
