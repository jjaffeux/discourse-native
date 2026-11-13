abstract interface class TopicReadsApi {
  static const maximumPostsPerRequest = 100;

  Future<void> recordTopicReads({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postNumbers,
    int milliseconds = 500,
    String? clientId,
  });
}
