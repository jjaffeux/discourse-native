import '../data/site_lifecycle.dart';
import '../models/post.dart';
import '../models/topic.dart';

/// What the feed and topic loaders may ask of the last launch.
///
/// Every answer is stale by definition. A loader publishes one only where no
/// response has landed, and always goes on to ask the site.
abstract interface class FeedSnapshots {
  Future<TopicList?> feed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
  );

  void rememberFeed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
    TopicList list,
  );
}

abstract interface class TopicSnapshots {
  Future<TopicPayload?> topic(String siteUrl, SiteLease lease, int topicId);

  void rememberTopic(String siteUrl, SiteLease lease, TopicPayload payload);
}
