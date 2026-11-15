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

/// Implemented by a transport that can tell when a site answers again, which
/// is when read timings held back by a failure are worth offering once more.
abstract interface class OriginSuccessSource {
  /// Tells [observer] the origin of each request answered with success,
  /// until the returned callback is called.
  void Function() onOriginSuccess(void Function(String origin) observer);
}
