import '../data/site_lifecycle.dart';

final class PostPermanentDeleteTarget {
  PostPermanentDeleteTarget.capture({
    required this.siteUrl,
    required this.topicId,
    required this.postId,
    required this.postNumber,
    required SiteLifecycle lifecycle,
  }) : lease = lifecycle.capture(siteUrl);

  final String siteUrl;
  final int topicId;
  final int postId;
  final int postNumber;
  final SiteLease lease;

  bool get deletesTopic => postNumber == 1;
}

final class PostNoticeTarget {
  PostNoticeTarget.capture({
    required this.siteUrl,
    required this.topicId,
    required this.postId,
    required SiteLifecycle lifecycle,
  }) : lease = lifecycle.capture(siteUrl);

  final String siteUrl;
  final int topicId;
  final int postId;
  final SiteLease lease;
}

final class TopicPostMoveTarget {
  TopicPostMoveTarget.capture({
    required this.siteUrl,
    required this.topicId,
    required this.privateMessage,
    required SiteLifecycle lifecycle,
  }) : lease = lifecycle.capture(siteUrl);

  final String siteUrl;
  final int topicId;

  /// Whether the source was a message when the move was offered. Its posts
  /// move only into a message, and a source that has changed archetype since
  /// is refused rather than moved as the other kind.
  final bool privateMessage;
  final SiteLease lease;
}

final class TopicPostOwnerTarget {
  TopicPostOwnerTarget.capture({
    required this.siteUrl,
    required this.topicId,
    required this.postId,
    required SiteLifecycle lifecycle,
  }) : lease = lifecycle.capture(siteUrl);

  final String siteUrl;
  final int topicId;

  // Null retains selected-post mode: read the topic's selection on submit.
  final int? postId;
  final SiteLease lease;
}
