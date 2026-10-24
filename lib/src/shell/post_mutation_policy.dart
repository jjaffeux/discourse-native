part of 'shell_controller.dart';

final class _PostMutationPolicy {
  const _PostMutationPolicy({
    required this.store,
    required this.instanceFor,
    required this.selectedSite,
    required this.isDisposed,
  });

  final Store store;
  final DiscourseInstance? Function(String siteUrl) instanceFor;
  final String? Function() selectedSite;
  final bool Function() isDisposed;

  PostMutationProblem problem(WriteException error) => PostMutationProblem(
    switch (error.failure) {
      WriteFailure.validation => PostMutationProblemKind.validation,
      WriteFailure.rateLimited => PostMutationProblemKind.rateLimited,
      WriteFailure.forbidden => PostMutationProblemKind.forbidden,
      WriteFailure.conflict => PostMutationProblemKind.conflict,
      WriteFailure.unreachable => PostMutationProblemKind.unavailable,
    },
    serverMessages: List.unmodifiable(error.errors),
    retryAfter: error.retryAfter,
  );

  PostMutationOutcome retired(PostMutationOutcome outcome) => switch (outcome) {
    PostMutationAccepted() => const PostMutationAccepted.retired(),
    PostMutationUncertain(:final recovery) => PostMutationUncertain(
      PostProjectionFreshness.retired,
      recovery,
    ),
    _ => const PostMutationRetired(),
  };

  PostMutationAccepted accepted(
    PostProjectionFreshness projection,
    PostMutationRecovery recovery,
  ) => switch (projection) {
    PostProjectionFreshness.fresh => const PostMutationAccepted.fresh(),
    PostProjectionFreshness.stale => PostMutationAccepted.stale(recovery),
    PostProjectionFreshness.retired => const PostMutationAccepted.retired(),
  };

  Future<PostMutationOutcome> failed(
    TopicDataSession data,
    int topicId,
    List<int> ids,
    String? apiKey,
    Object error,
    StackTrace stackTrace, {
    required bool sent,
    bool wholeTopic = false,
    bool alreadyHeld = true,
  }) async {
    if (!sent) {
      if (!data.isCurrent || isDisposed()) return const PostMutationRetired();
      return PostMutationNotSent(
        error is WriteException
            ? problem(error)
            : const PostMutationProblem(PostMutationProblemKind.unavailable),
      );
    }
    if (error is WriteException &&
        (error.failure != WriteFailure.unreachable || error.notSent)) {
      if (!data.isCurrent || isDisposed()) return const PostMutationRetired();
      final failure = problem(error);
      return error.notSent
          ? PostMutationNotSent(failure)
          : PostMutationRefused(failure);
    }

    return data.reconcileUncertainMutation(
      topicId,
      ids,
      apiKey,
      wholeTopic: wholeTopic,
      alreadyHeld: alreadyHeld,
    );
  }

  PostMutationOutcome? moveBlock(
    TopicPostMoveTarget target, {
    List<int>? postIds,
    bool newTopic = false,
  }) {
    if (isDisposed() || !target._lease.isCurrent) {
      return const PostMutationRetired();
    }
    final topic = store.read<TopicDetail>(target.siteUrl, target.topicId);
    const forbidden = PostMutationNotSent(
      PostMutationProblem(PostMutationProblemKind.forbidden),
    );
    if (topic == null || !topic.canMovePosts) return forbidden;
    // A move is sent with the archetype it was offered in, and one sent as a
    // topic publishes a message's posts in a new public topic.
    if (topic.privateMessage != target.privateMessage) return forbidden;
    if (postIds == null) return null;
    if (postIds.isEmpty ||
        postIds.any(
          (id) =>
              !topic.stream.contains(id) ||
              store.read<Post>(target.siteUrl, id) == null,
        )) {
      return forbidden;
    }
    if (newTopic &&
        (postIds.length == topic.stream.length ||
            store.read<Post>(target.siteUrl, postIds.first)?.postType !=
                Post.regularPostType ||
            (target.privateMessage &&
                instanceFor(target.siteUrl)?.user?.admin != true))) {
      return forbidden;
    }
    return null;
  }

  PostMutationOutcome? ownerRefusal(
    TopicPostOwnerTarget target,
    List<int> postIds,
    String username,
  ) {
    if (isDisposed() || !target._lease.isCurrent) {
      return const PostMutationRetired();
    }
    final instance = instanceFor(target.siteUrl);
    final topic = store.read<TopicDetail>(target.siteUrl, target.topicId);
    final posts = [
      for (final id in postIds) ?store.read<Post>(target.siteUrl, id),
    ];
    if (instance?.isConnected != true ||
        instance?.user?.canChangePostOwner != true ||
        topic == null ||
        (target.postId == null &&
            (selectedSite() != target.siteUrl || !topic.canSelectPosts)) ||
        postIds.isEmpty ||
        posts.length != postIds.length ||
        postIds.any((id) => !topic.stream.contains(id)) ||
        posts.map((post) => post.username).toSet().length != 1 ||
        username.isEmpty ||
        posts.first.username == username) {
      return const PostMutationNotSent(
        PostMutationProblem(PostMutationProblemKind.forbidden),
      );
    }
    return null;
  }
}
