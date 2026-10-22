part of 'shell_controller.dart';

typedef _SelectedPostsKey = ({String siteUrl, int topicId});

final class _SelectedPostsSelection {
  final Set<int> ids = {};
  _SelectedPostsAttempt? active;
}

sealed class _SelectedPostsCommand {
  const _SelectedPostsCommand(this.siteUrl, this.topicId, this.lease);

  final String siteUrl;
  final int topicId;
  final SiteLease lease;

  _SelectedPostsKey get key => (siteUrl: siteUrl, topicId: topicId);
}

final class _DeleteSelectedPosts extends _SelectedPostsCommand {
  const _DeleteSelectedPosts(super.siteUrl, super.topicId, super.lease);
}

final class _MergeSelectedPosts extends _SelectedPostsCommand {
  const _MergeSelectedPosts(super.siteUrl, super.topicId, super.lease);
}

final class _MoveSelectedPostsToExisting extends _SelectedPostsCommand {
  _MoveSelectedPostsToExisting(
    this.target,
    this.destinationTopicId, {
    this.chronologicalOrder = false,
  }) : super(target.siteUrl, target.topicId, target._lease);

  final TopicPostMoveTarget target;
  final int destinationTopicId;
  final bool chronologicalOrder;
}

final class _MoveSelectedPostsToNew extends _SelectedPostsCommand {
  _MoveSelectedPostsToNew(
    this.target, {
    required this.title,
    this.categoryId,
    List<int> tagIds = const [],
  }) : tagIds = List<int>.unmodifiable(tagIds),
       super(target.siteUrl, target.topicId, target._lease);

  final TopicPostMoveTarget target;
  final String title;
  final int? categoryId;
  final List<int> tagIds;
}

final class _ChangeSelectedPostsOwner extends _SelectedPostsCommand {
  _ChangeSelectedPostsOwner(this.target, String username)
    : username = username.trim(),
      super(target.siteUrl, target.topicId, target._lease);

  final TopicPostOwnerTarget target;
  final String username;
}

final class _SelectedPostsAttempt {
  _SelectedPostsAttempt({
    required this.command,
    required this.selection,
    required List<int> postIds,
    required this.data,
    required List<void Function()> releases,
  }) : postIds = List<int>.unmodifiable(postIds),
       releases = List<void Function()>.unmodifiable(releases);

  final _SelectedPostsCommand command;
  final _SelectedPostsSelection selection;
  final List<int> postIds;
  final TopicDataSession data;
  final List<void Function()> releases;
}
