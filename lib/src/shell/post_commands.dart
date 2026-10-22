part of 'shell_controller.dart';

sealed class _PostCommand {
  const _PostCommand();

  int? get postId;
}

sealed class _PostSnapshotCommand extends _PostCommand {
  const _PostSnapshotCommand(this.post);

  final Post post;

  @override
  int get postId => post.id;
}

final class _DeletePost extends _PostSnapshotCommand {
  const _DeletePost(super.post);
}

final class _RecoverPost extends _PostSnapshotCommand {
  const _RecoverPost(super.post);
}

final class _SetPostWiki extends _PostSnapshotCommand {
  const _SetPostWiki(super.post, this.wiki);

  final bool wiki;
}

final class _SetPostLocked extends _PostSnapshotCommand {
  const _SetPostLocked(super.post, this.locked);

  final bool locked;
}

final class _UnhidePost extends _PostSnapshotCommand {
  const _UnhidePost(super.post);
}

final class _TogglePostType extends _PostSnapshotCommand {
  const _TogglePostType(super.post);
}

final class _ChangePostOwner extends _PostCommand {
  _ChangePostOwner(this.target, String username) : username = username.trim();

  final TopicPostOwnerTarget target;
  final String username;

  @override
  int? get postId => target.postId;
}

final class _PermanentlyDeleteReply extends _PostCommand {
  const _PermanentlyDeleteReply(this.target);

  final PostPermanentDeleteTarget target;

  @override
  int get postId => target.postId;
}

final class _AdmittedPostCommand {
  const _AdmittedPostCommand({
    required this.command,
    required this.data,
    required this.siteUrl,
    required this.topicId,
    required this.postId,
    required this.lease,
  });

  final _PostCommand command;
  final TopicDataSession data;
  final String siteUrl;
  final int topicId;
  final int postId;
  final SiteLease lease;
}

final class _PostCommandOwner {
  const _PostCommandOwner(this.shell);

  final ShellController shell;

  static const _invalidTarget = PostMutationNotSent(
    PostMutationProblem(PostMutationProblemKind.invalidTarget),
  );

  PostMutationOutcome? _targetBlock(_PostCommand command) => switch (command) {
    _ChangePostOwner(:final target, :final username) =>
      target.postId == null
          ? const PostMutationNotSent(
              PostMutationProblem(PostMutationProblemKind.forbidden),
            )
          : shell._topicPostOwnerRefusal(target, [target.postId!], username),
    _PermanentlyDeleteReply(:final target) => shell._permanentPostDeletionBlock(
      target,
    ),
    _PostSnapshotCommand() => null,
  };

  PostMutationOutcome? _admissionBlock(
    _PostCommand command,
  ) => switch (command) {
    _RecoverPost(:final post) when !post.canRecover => _invalidTarget,
    _SetPostWiki(:final post) when !post.canWiki => _invalidTarget,
    _SetPostWiki(:final post, :final wiki) when post.wiki == wiki =>
      const PostMutationNoChange(),
    _SetPostLocked(:final post) when !shell.canLockPost(post) => _invalidTarget,
    _SetPostLocked(:final post, :final locked) when post.locked == locked =>
      const PostMutationNoChange(),
    _UnhidePost(:final post) when !shell.canUnhidePost(post) => _invalidTarget,
    _TogglePostType(:final post) when !shell.canTogglePostType(post) =>
      _invalidTarget,
    _ => _targetBlock(command),
  };

  Future<void> _send(_AdmittedPostCommand attempt, String apiKey) {
    final mutations = shell.api.postMutations;
    final siteUrl = attempt.siteUrl;
    final topicId = attempt.topicId;
    final postId = attempt.postId;
    return switch (attempt.command) {
      _DeletePost() => mutations.deletePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: postId,
      ),
      _RecoverPost() => mutations.recoverPost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: postId,
      ),
      _SetPostWiki(:final wiki) => mutations.updatePostWiki(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: postId,
        wiki: wiki,
      ),
      _SetPostLocked(:final locked) => mutations.updatePostLocked(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: postId,
        locked: locked,
      ),
      _UnhidePost() => mutations.unhidePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: postId,
      ),
      _TogglePostType(:final post) => mutations.updatePostType(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: postId,
        postType: post.isModeratorAction
            ? Post.regularPostType
            : Post.moderatorPostType,
      ),
      _ChangePostOwner(:final username) => mutations.changePostOwners(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postIds: [postId],
        username: username,
      ),
      _PermanentlyDeleteReply() => mutations.permanentlyDeletePost(
        siteUrl: siteUrl,
        apiKey: apiKey,
        topicId: topicId,
        postId: postId,
      ),
    };
  }

  Future<PostMutationOutcome> run(_PostCommand command) async {
    if (_admissionBlock(command) case final refusal?) return refusal;
    final context = switch (command) {
      _ChangePostOwner(:final target) => (
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        lease: target._lease,
      ),
      _PermanentlyDeleteReply(:final target) => (
        siteUrl: target.siteUrl,
        topicId: target.topicId,
        lease: target._lease,
      ),
      _PostSnapshotCommand() => null,
    };
    final siteUrl = context?.siteUrl ?? shell.currentInstance?.url;
    final topicId = context?.topicId ?? shell.currentContent?.topicId;
    if (siteUrl == null || topicId == null) return _invalidTarget;
    final lease = context?.lease ?? shell.lifecycle.capture(siteUrl);
    final data = shell._topicData.forLease(siteUrl, lease);
    if (data == null || shell.accountSessionDisposed) {
      return const PostMutationRetired();
    }
    final attempt = _AdmittedPostCommand(
      command: command,
      data: data,
      siteUrl: siteUrl,
      topicId: topicId,
      postId: command.postId!,
      lease: lease,
    );
    if (_targetBlock(command) case final refusal?) return refusal;
    final unresolved = attempt.data.moderationRecoveryFor(topicId, [
      attempt.postId,
    ]);
    if (unresolved != null) {
      return PostMutationNotSent.recoveryRequired(unresolved);
    }
    final release = attempt.data.beginPostWrite(attempt.postId);
    if (release == null) {
      return const PostMutationNotSent(
        PostMutationProblem(PostMutationProblemKind.busyPost),
      );
    }
    try {
      if (!attempt.data.isCurrent || shell.accountSessionDisposed) {
        return const PostMutationRetired();
      }
      if (_targetBlock(command) case final refusal?) return refusal;
      final credential = await shell._credentialForWrite(siteUrl, lease: lease);
      if (!attempt.data.isCurrent || shell.accountSessionDisposed) {
        return const PostMutationRetired();
      }
      if (_targetBlock(command) case final refusal?) return refusal;
      if (credential.failure case final failure?) {
        return PostMutationNotSent(shell._postMutationProblem(failure));
      }
      var sent = false;
      try {
        await credential.request!.run(() {
          sent = true;
          return _send(attempt, credential.apiKey!);
        });
      } catch (error, stackTrace) {
        return await shell._failedPostMutation(
          attempt.data,
          topicId,
          [attempt.postId],
          credential.apiKey,
          error,
          stackTrace,
          sent: sent,
        );
      }
      if (!attempt.data.isCurrent || shell.accountSessionDisposed) {
        return const PostMutationAccepted.retired();
      }
      if (command case _RecoverPost(:final post) when post.postNumber == 1) {
        // PostDestroyer recovers the topic but only publishes its stats.
        lease.commit(() {
          shell._applyTopicDeletion(siteUrl, topicId, false, lease);
          shell._notify();
        });
      }
      final projection = await attempt.data.repairPost(
        topicId,
        attempt.postId,
        credential.apiKey,
        lease,
      );
      return shell._acceptedPostMutation(
        projection,
        attempt.data.postMutationRecovery(topicId, [
          attempt.postId,
        ], credential.apiKey),
      );
    } finally {
      lease.commit(release);
    }
  }
}
