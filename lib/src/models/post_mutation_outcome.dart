enum PostProjectionFreshness { fresh, stale, retired }

enum PostMutationProblemKind {
  validation,
  rateLimited,
  forbidden,
  conflict,
  unavailable,
  busyPost,
  busyTopic,
  invalidTarget,
  permanentDeletionUnavailable,
  recoveryRequired,
}

final class PostMutationProblem {
  const PostMutationProblem(
    this.kind, {
    this.serverMessages = const [],
    this.retryAfter,
  });

  final PostMutationProblemKind kind;
  final List<String> serverMessages;
  final Duration? retryAfter;
}

abstract interface class PostMutationRecovery {
  bool get isCurrent;
  Future<PostProjectionFreshness> refresh();
}

sealed class PostMutationOutcome {
  const PostMutationOutcome();
}

final class PostMutationAccepted extends PostMutationOutcome {
  const PostMutationAccepted.fresh()
    : projection = PostProjectionFreshness.fresh,
      recovery = null;
  const PostMutationAccepted.stale(PostMutationRecovery this.recovery)
    : projection = PostProjectionFreshness.stale;
  const PostMutationAccepted.retired()
    : projection = PostProjectionFreshness.retired,
      recovery = null;

  final PostProjectionFreshness projection;
  final PostMutationRecovery? recovery;
}

final class PostMutationRefused extends PostMutationOutcome {
  const PostMutationRefused(this.problem);
  final PostMutationProblem problem;
}

final class PostMutationNotSent extends PostMutationOutcome {
  const PostMutationNotSent(this.problem) : recovery = null;
  const PostMutationNotSent.recoveryRequired(PostMutationRecovery this.recovery)
    : problem = const PostMutationProblem(
        PostMutationProblemKind.recoveryRequired,
      );
  final PostMutationProblem problem;
  final PostMutationRecovery? recovery;
}

final class PostMutationUncertain extends PostMutationOutcome {
  const PostMutationUncertain(this.projection, this.recovery);
  final PostProjectionFreshness projection;
  final PostMutationRecovery recovery;
}

final class PostMutationRetired extends PostMutationOutcome {
  const PostMutationRetired();
}

final class PostMutationNoChange extends PostMutationOutcome {
  const PostMutationNoChange();
}

final class PostMoveOutcome {
  PostMoveOutcome(
    this.outcome, {
    String? destinationUrl,
    required bool targetCurrent,
  }) : destinationUrl =
           targetCurrent &&
               outcome is PostMutationAccepted &&
               outcome.projection != PostProjectionFreshness.retired
           ? destinationUrl
           : null;

  final PostMutationOutcome outcome;
  final String? destinationUrl;
}
