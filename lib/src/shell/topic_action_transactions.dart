part of 'shell_controller.dart';

final class _TopicActionTransactions {
  _TopicActionTransactions({
    required this.store,
    required this.credentials,
    required this.lifecycle,
    required this.topics,
    required this.topicData,
    required this.instanceAt,
    required this.changed,
    required this.topicRemoved,
    required this.mutationProblem,
    required this.failedMutation,
  });

  final Store store;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final TopicMutationsApi topics;
  final TopicDataOwner topicData;
  final DiscourseInstance? Function(String siteUrl) instanceAt;
  final void Function() changed;
  final void Function(String siteUrl, int topicId) topicRemoved;
  final PostMutationProblem Function(WriteException error) mutationProblem;
  final Future<PostMutationOutcome> Function(
    TopicDataSession data,
    int topicId,
    List<int> ids,
    String? apiKey,
    Object error,
    StackTrace stackTrace, {
    required bool sent,
    required bool wholeTopic,
    required bool alreadyHeld,
  })
  failedMutation;

  final Set<String> _topicPinWrites = {};
  final Set<String> _topicStatusWrites = {};
  final Set<String> _topicDeletionWrites = {};
  bool _disposed = false;

  void forget(String siteUrl) {
    _topicPinWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicStatusWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
    _topicDeletionWrites.removeWhere((key) => key.startsWith('$siteUrl#'));
  }

  void dispose() {
    _disposed = true;
    _topicPinWrites.clear();
    _topicStatusWrites.clear();
    _topicDeletionWrites.clear();
  }

  bool topicPinWriteInFlight(String siteUrl, int topicId) =>
      _topicPinWrites.contains('$siteUrl#$topicId');

  Future<String?> updateTopicPinPreference(
    String siteUrl,
    int topicId,
    bool pinned,
  ) async {
    if (_disposed || topicId <= 0) {
      return appL10n.thisTopicCanNoLongerBeChanged;
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null || !held.hasPinPreference) {
      return appL10n.thisTopicDoesNotOfferAPinPreference;
    }
    if (held.pinned == pinned) return null;

    final key = '$siteUrl#$topicId';
    if (!_topicPinWrites.add(key)) {
      return appL10n.anotherPinChangeIsStillFinishing;
    }
    final heldRow = store.read<Topic>(siteUrl, topicId);
    final lease = lifecycle.capture(siteUrl);

    void project(bool nextPinned, bool nextUnpinned) {
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.copyWith(pinned: nextPinned, unpinned: nextUnpinned),
        );
        store.update<Topic>(
          siteUrl,
          topicId,
          (topic) => topic.copyWith(pinned: nextPinned),
        );
        changed();
      });
    }

    void rollback() {
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.pinned == pinned && topic.unpinned == !pinned
              ? topic.copyWith(pinned: held.pinned, unpinned: held.unpinned)
              : topic,
        );
        if (heldRow != null) {
          store.update<Topic>(
            siteUrl,
            topicId,
            (topic) => topic.pinned == pinned
                ? topic.copyWith(pinned: heldRow.pinned)
                : topic,
          );
        }
        changed();
      });
    }

    project(pinned, !pinned);
    try {
      final credential = await _topicActionCredential(
        credentials,
        siteUrl,
        lease,
      );
      if (!lease.isCurrent || _disposed) return null;
      if (credential.failure case final failure?) {
        rollback();
        return failure.message;
      }
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || _disposed) return null;
      await credential.request!.run(
        () => topics.updateTopicPinForUser(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          pinned: pinned,
          clientId: clientId,
        ),
      );
      return null;
    } on WriteException catch (error) {
      if (lease.isCurrent && !_disposed) rollback();
      return error.message;
    } catch (error) {
      if (lease.isCurrent && !_disposed) {
        rollback();
      }
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() {
        _topicPinWrites.remove(key);
        if (!_disposed) changed();
      });
    }
  }

  bool topicStatusWriteInFlight(String siteUrl, int topicId) =>
      _topicStatusWrites.contains('$siteUrl#$topicId');

  Future<String?> updateTopicStatus(
    String siteUrl,
    int topicId,
    TopicStatusProperty status,
    bool enabled,
  ) async {
    if (_disposed || topicId <= 0) {
      return appL10n.thisTopicCanNoLongerBeChanged;
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null || !held.canChangeStatus(status)) {
      return appL10n.thisTopicCanNoLongerBeChangedThatWay;
    }
    if (held.statusValue(status) == enabled) return null;

    final key = '$siteUrl#$topicId';
    if (!_topicStatusWrites.add(key)) {
      return appL10n.anotherTopicActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    changed();
    try {
      final credential = await _topicActionCredential(
        credentials,
        siteUrl,
        lease,
      );
      if (!lease.isCurrent || _disposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || _disposed) return null;
      await credential.request!.run(
        () => topics.updateTopicStatus(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
          topicId: topicId,
          status: status,
          enabled: enabled,
          clientId: clientId,
        ),
      );
      if (!lease.isCurrent || _disposed) return null;
      lease.commit(() {
        store.update<TopicDetail>(
          siteUrl,
          topicId,
          (topic) => topic.withStatus(status, enabled),
        );
        if (status == TopicStatusProperty.closed) {
          store.update<Topic>(
            siteUrl,
            topicId,
            (topic) => topic.copyWith(closed: enabled),
          );
        }
        changed();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() {
        _topicStatusWrites.remove(key);
        if (!_disposed) changed();
      });
    }
  }

  bool topicDeletionWriteInFlight(String siteUrl, int topicId) =>
      _topicDeletionWrites.contains('$siteUrl#$topicId');

  Future<String?> setTopicDeleted(
    String siteUrl,
    int topicId,
    bool deleted,
  ) async {
    if (_disposed || topicId <= 0) {
      return appL10n.thisTopicCanNoLongerBeChanged;
    }
    final held = store.read<TopicDetail>(siteUrl, topicId);
    final allowed = deleted
        ? held?.canDeleteTopic == true
        : held?.canRecoverTopic == true;
    if (held == null || !allowed) {
      return deleted
          ? appL10n.thisTopicCannotBeDeleted
          : appL10n.thisTopicCannotBeRecovered;
    }
    if (topicData
            .forSite(siteUrl)
            .moderationRecoveryFor(topicId, const [], wholeTopic: true) !=
        null) {
      return appL10n.postMutationRecoveryRequired;
    }
    final key = '$siteUrl#$topicId';
    if (!_topicDeletionWrites.add(key)) {
      return appL10n.anotherTopicActionIsStillFinishing;
    }
    final lease = lifecycle.capture(siteUrl);
    changed();
    try {
      final credential = await _topicActionCredential(
        credentials,
        siteUrl,
        lease,
      );
      if (!lease.isCurrent || _disposed) return null;
      if (credential.failure case final failure?) return failure.message;
      final clientId = credential.request!.clientId;
      if (!lease.isCurrent || _disposed) return null;
      if (deleted) {
        await credential.request!.run(
          () => topics.deleteTopic(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: topicId,
            clientId: clientId,
          ),
        );
      } else {
        await credential.request!.run(
          () => topics.recoverTopic(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: topicId,
            clientId: clientId,
          ),
        );
      }
      if (!lease.isCurrent || _disposed) return null;
      lease.commit(() {
        _applyTopicDeletion(siteUrl, topicId, deleted, lease);
        changed();
      });
      return null;
    } on WriteException catch (error) {
      return error.message;
    } catch (error) {
      return const WriteException(WriteFailure.unreachable).message;
    } finally {
      lease.commit(() {
        _topicDeletionWrites.remove(key);
        if (!_disposed) changed();
      });
    }
  }

  /// Applies an accepted deletion or recovery of a topic. Neither endpoint
  /// answers with the topic, so the held one takes what PostDestroyer is known
  /// to do to it, its list row follows the closed state, and it is read again
  /// for what that leaves to the server.
  void _applyTopicDeletion(
    String siteUrl,
    int topicId,
    bool deleted,
    SiteLease lease,
  ) {
    final data = topicData.forLease(siteUrl, lease);
    if (data == null) return;
    final held = store.read<TopicDetail>(siteUrl, topicId);
    if (held == null) return;
    final next = deleted
        ? held.afterDeletion(DateTime.now().toUtc())
        : held.afterRecovery();
    if (identical(next, held)) return;
    store.update<TopicDetail>(siteUrl, topicId, (_) => next);
    if (!lease.isCurrent) return;
    if (next.closed != held.closed) {
      store.update<Topic>(
        siteUrl,
        topicId,
        (row) => row.copyWith(closed: next.closed),
      );
    }
    if (!deleted) {
      // Only the server knows whether the recovered topic takes replies again.
      unawaited(data.refresh(topicId, slug: ''));
      return;
    }
    // Site settings decide whether an author's deletion withdrew or trashed
    // the topic, and a deleter may no longer be allowed to read a trashed
    // one, so it is read when next opened rather than now.
    data.refreshWhenOpened(topicId);
  }

  bool _canPermanentlyDeletePost(TopicDetail topic, Post post) =>
      post.isDeleted &&
      topic.stream.contains(post.id) &&
      (post.postNumber == 1
          ? topic.deletedAt != null && topic.canPermanentlyDelete
          : post.canPermanentlyDelete);

  PostMutationOutcome? _permanentPostDeletionBlock(
    PostPermanentDeleteTarget target,
  ) {
    if (_disposed || !target._lease.isCurrent) {
      return const PostMutationRetired();
    }
    final topic = store.read<TopicDetail>(target.siteUrl, target.topicId);
    final post = store.read<Post>(target.siteUrl, target.postId);
    if (instanceAt(target.siteUrl)?.isConnected != true ||
        topic == null ||
        post == null ||
        post.postNumber != target.postNumber ||
        !_canPermanentlyDeletePost(topic, post)) {
      return const PostMutationNotSent(
        PostMutationProblem(
          PostMutationProblemKind.permanentDeletionUnavailable,
        ),
      );
    }
    return null;
  }

  Future<PostMutationOutcome> permanentlyDeleteTopic(
    PostPermanentDeleteTarget target,
  ) async {
    if (_permanentPostDeletionBlock(target) case final refusal?) return refusal;
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final postId = target.postId;
    final lease = target._lease;
    final data = topicData.forLease(siteUrl, lease);
    if (data == null) return const PostMutationRetired();
    final unresolved = data.moderationRecoveryFor(topicId, [
      postId,
    ], wholeTopic: target.deletesTopic);
    if (unresolved != null) {
      return PostMutationNotSent.recoveryRequired(unresolved);
    }
    final topicKey = '$siteUrl#$topicId';
    if (!_topicDeletionWrites.add(topicKey)) {
      return const PostMutationNotSent(
        PostMutationProblem(PostMutationProblemKind.busyTopic),
      );
    }
    final ids = List<int>.unmodifiable(
      store.read<TopicDetail>(siteUrl, topicId)?.stream ?? [postId],
    );
    changed();
    try {
      if (_permanentPostDeletionBlock(target) case final refusal?) {
        return refusal;
      }
      final credential = await _topicActionCredential(
        credentials,
        siteUrl,
        lease,
      );
      if (_permanentPostDeletionBlock(target) case final refusal?) {
        return refusal;
      }
      if (credential.failure case final failure?) {
        return PostMutationNotSent(mutationProblem(failure));
      }
      var sent = false;
      try {
        await credential.request!.run(() {
          sent = true;
          return topics.permanentlyDeleteTopic(
            siteUrl: siteUrl,
            apiKey: credential.apiKey!,
            topicId: topicId,
            clientId: credential.request!.clientId,
          );
        });
      } catch (error, stackTrace) {
        return await failedMutation(
          data,
          topicId,
          ids,
          credential.apiKey,
          error,
          stackTrace,
          sent: sent,
          wholeTopic: true,
          alreadyHeld: false,
        );
      }
      if (!data.isCurrent || _disposed) {
        return const PostMutationAccepted.retired();
      }
      data.removeTopicPermanently(topicId);
      changed();
      if (!data.isCurrent || _disposed) {
        return const PostMutationAccepted.retired();
      }
      topicRemoved(siteUrl, topicId);
      return data.isCurrent && !_disposed
          ? const PostMutationAccepted.fresh()
          : const PostMutationAccepted.retired();
    } finally {
      lease.commit(() {
        _topicDeletionWrites.remove(topicKey);
        changed();
      });
    }
  }
}
