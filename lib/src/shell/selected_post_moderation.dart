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

  void releaseHolds() {
    for (final release in releases) {
      release();
    }
  }
}

final class _SelectedPostModeration {
  _SelectedPostModeration({
    required this.store,
    required this.api,
    required this.credentials,
    required this.lifecycle,
    required this.topicData,
    required this.policy,
    required this.changed,
  });

  final Store store;
  final PostMutationsApi api;
  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final TopicDataOwner topicData;
  final _PostMutationPolicy policy;
  final void Function() changed;
  final Map<_SelectedPostsKey, _SelectedPostsSelection> _selectedPosts = {};
  bool _disposed = false;

  void forget(String siteUrl) =>
      _selectedPosts.removeWhere((key, _) => key.siteUrl == siteUrl);

  void dispose() {
    _disposed = true;
    _selectedPosts.clear();
  }

  bool topicPostSelectionEnabled(String siteUrl, int topicId) =>
      _selectedPosts.containsKey((siteUrl: siteUrl, topicId: topicId));

  Set<int> selectedTopicPostIds(String siteUrl, int topicId) =>
      Set.unmodifiable(
        _selectedPosts[(siteUrl: siteUrl, topicId: topicId)]?.ids ??
            const <int>{},
      );

  bool isTopicPostSelected(String siteUrl, int topicId, int postId) =>
      _selectedPosts[(siteUrl: siteUrl, topicId: topicId)]?.ids.contains(
        postId,
      ) ??
      false;

  List<Post> selectedTopicPosts(String siteUrl, int topicId) {
    final detail = store.read<TopicDetail>(siteUrl, topicId);
    final selected = _selectedPosts[(siteUrl: siteUrl, topicId: topicId)]?.ids;
    if (detail == null || selected == null || selected.isEmpty) return const [];
    return List.unmodifiable([
      for (final id in detail.stream)
        if (selected.contains(id)) ?store.read<Post>(siteUrl, id),
    ]);
  }

  bool topicPostSelectionWriteInFlight(String siteUrl, int topicId) =>
      _selectedPosts[(siteUrl: siteUrl, topicId: topicId)]?.active != null;

  void setTopicPostSelectionEnabled(String siteUrl, int topicId, bool enabled) {
    final key = (siteUrl: siteUrl, topicId: topicId);
    if (enabled) {
      final topic = store.read<TopicDetail>(siteUrl, topicId);
      if (topic == null || !topic.canSelectPosts) return;
      if (_selectedPosts.containsKey(key)) return;
      _selectedPosts[key] = _SelectedPostsSelection();
    } else {
      if (_selectedPosts[key]?.active != null ||
          _selectedPosts.remove(key) == null) {
        return;
      }
    }
    changed();
  }

  void toggleTopicPostSelected(String siteUrl, int topicId, int postId) {
    final selection = _selectedPosts[(siteUrl: siteUrl, topicId: topicId)];
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (selection == null ||
        topic == null ||
        !topic.canSelectPosts ||
        selection.active != null ||
        !topic.stream.contains(postId) ||
        store.read<Post>(siteUrl, postId) == null) {
      return;
    }
    if (!selection.ids.remove(postId)) selection.ids.add(postId);
    changed();
  }

  void selectAllLoadedTopicPosts(String siteUrl, int topicId) {
    final selection = _selectedPosts[(siteUrl: siteUrl, topicId: topicId)];
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (selection == null ||
        topic == null ||
        !topic.canSelectPosts ||
        selection.active != null) {
      return;
    }
    selection.ids
      ..clear()
      ..addAll(
        topic.stream.where((id) => store.read<Post>(siteUrl, id) != null),
      );
    changed();
  }

  void clearSelectedTopicPosts(String siteUrl, int topicId) {
    final selection = _selectedPosts[(siteUrl: siteUrl, topicId: topicId)];
    if (selection == null ||
        selection.ids.isEmpty ||
        selection.active != null) {
      return;
    }
    selection.ids.clear();
    changed();
  }

  Future<PostMutationOutcome> deleteSelectedTopicPosts(
    String siteUrl,
    int topicId,
  ) async {
    final posts = selectedTopicPosts(siteUrl, topicId);
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null ||
        !topic.canSelectPosts ||
        posts.isEmpty ||
        posts.any((post) => !post.canDelete)) {
      return const PostMutationNotSent(
        PostMutationProblem(PostMutationProblemKind.invalidTarget),
      );
    }
    return (await _runSelectedPosts(
      _DeleteSelectedPosts(siteUrl, topicId, lifecycle.capture(siteUrl)),
      posts,
    )).outcome;
  }

  Future<PostMutationOutcome> mergeSelectedTopicPosts(
    String siteUrl,
    int topicId,
  ) async {
    final posts = selectedTopicPosts(siteUrl, topicId);
    final topic = store.read<TopicDetail>(siteUrl, topicId);
    if (topic == null ||
        !topic.canSelectPosts ||
        posts.length < 2 ||
        posts.any((post) => !post.canDelete) ||
        posts.map((post) => post.username).toSet().length != 1) {
      return const PostMutationNotSent(
        PostMutationProblem(PostMutationProblemKind.invalidTarget),
      );
    }
    return (await _runSelectedPosts(
      _MergeSelectedPosts(siteUrl, topicId, lifecycle.capture(siteUrl)),
      posts,
    )).outcome;
  }

  Future<PostMoveOutcome> moveSelectedTopicPostsToExisting(
    TopicPostMoveTarget target,
    int destinationTopicId, {
    bool chronologicalOrder = false,
  }) async {
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final posts = selectedTopicPosts(siteUrl, topicId);
    final ids = [for (final post in posts) post.id];
    final refusal = policy.moveBlock(target, postIds: ids);
    if (refusal != null) return PostMoveOutcome(refusal, targetCurrent: false);
    if (destinationTopicId <= 0 || destinationTopicId == topicId) {
      return PostMoveOutcome(
        const PostMutationNotSent(
          PostMutationProblem(PostMutationProblemKind.forbidden),
        ),
        targetCurrent: true,
      );
    }
    final settlement = await _runSelectedPosts(
      _MoveSelectedPostsToExisting(
        target,
        destinationTopicId,
        chronologicalOrder: chronologicalOrder,
      ),
      posts,
    );
    final outcome = settlement.outcome;
    final current = !_disposed && target._lease.isCurrent;
    return PostMoveOutcome(
      current ? outcome : policy.retired(outcome),
      destinationUrl: settlement.destinationUrl,
      targetCurrent: current,
    );
  }

  Future<PostMoveOutcome> moveSelectedTopicPostsToNew(
    TopicPostMoveTarget target, {
    required String title,
    int? categoryId,
    List<int> tagIds = const [],
  }) async {
    final siteUrl = target.siteUrl;
    final topicId = target.topicId;
    final posts = selectedTopicPosts(siteUrl, topicId);
    final ids = [for (final post in posts) post.id];
    final refusal = policy.moveBlock(target, postIds: ids, newTopic: true);
    if (refusal != null) return PostMoveOutcome(refusal, targetCurrent: false);
    if (title.trim().isEmpty || (target.privateMessage && categoryId != null)) {
      return PostMoveOutcome(
        const PostMutationNotSent(
          PostMutationProblem(PostMutationProblemKind.forbidden),
        ),
        targetCurrent: true,
      );
    }
    final settlement = await _runSelectedPosts(
      _MoveSelectedPostsToNew(
        target,
        title: title,
        categoryId: categoryId,
        tagIds: tagIds,
      ),
      posts,
    );
    final outcome = settlement.outcome;
    final current = !_disposed && target._lease.isCurrent;
    return PostMoveOutcome(
      current ? outcome : policy.retired(outcome),
      destinationUrl: settlement.destinationUrl,
      targetCurrent: current,
    );
  }

  bool canChangeSelectedTopicPostOwner(String siteUrl, int topicId) {
    if (policy.selectedSite() != siteUrl ||
        policy.instanceFor(siteUrl)?.user?.canChangePostOwner != true) {
      return false;
    }
    final posts = selectedTopicPosts(siteUrl, topicId);
    return posts.isNotEmpty &&
        posts.map((post) => post.username).toSet().length == 1;
  }

  Future<PostMutationOutcome> changeSelectedTopicPostOwner(
    TopicPostOwnerTarget target,
    String username,
  ) async {
    final posts = selectedTopicPosts(target.siteUrl, target.topicId);
    final ids = [for (final post in posts) post.id];
    final trimmed = username.trim();
    if (target.postId != null) {
      return const PostMutationNotSent(
        PostMutationProblem(PostMutationProblemKind.forbidden),
      );
    }
    if (policy.ownerRefusal(target, ids, trimmed) case final refusal?) {
      return refusal;
    }
    final settlement = await _runSelectedPosts(
      _ChangeSelectedPostsOwner(target, trimmed),
      posts,
    );
    final outcome = settlement.outcome;
    return (!_disposed && target._lease.isCurrent)
        ? outcome
        : policy.retired(outcome);
  }

  PostMutationOutcome? _selectedPostsDispatchBlock(
    _SelectedPostsCommand command,
    List<int> ids,
  ) => switch (command) {
    _MoveSelectedPostsToExisting(:final target) => policy.moveBlock(
      target,
      postIds: ids,
    ),
    _MoveSelectedPostsToNew(:final target) => policy.moveBlock(
      target,
      postIds: ids,
      newTopic: true,
    ),
    _ChangeSelectedPostsOwner(:final target, :final username) =>
      policy.ownerRefusal(target, ids, username),
    _DeleteSelectedPosts() || _MergeSelectedPosts() => null,
  };

  Future<String?> _sendSelectedPosts(
    _SelectedPostsAttempt attempt,
    String apiKey,
  ) async {
    final command = attempt.command;
    final siteUrl = command.siteUrl;
    final topicId = command.topicId;
    final ids = attempt.postIds;
    switch (command) {
      case _DeleteSelectedPosts():
        await api.deletePosts(siteUrl: siteUrl, apiKey: apiKey, postIds: ids);
        return null;
      case _MergeSelectedPosts():
        await api.mergePosts(siteUrl: siteUrl, apiKey: apiKey, postIds: ids);
        return null;
      case _MoveSelectedPostsToExisting(
        :final target,
        :final destinationTopicId,
        :final chronologicalOrder,
      ):
        void invalidateDestination() => command.lease.commit(
          () => attempt.data.refreshWhenOpened(destinationTopicId),
        );
        final String destinationUrl;
        try {
          destinationUrl = await api.movePosts(
            siteUrl: siteUrl,
            apiKey: apiKey,
            topicId: topicId,
            postIds: ids,
            destinationTopicId: destinationTopicId,
            chronologicalOrder: chronologicalOrder,
            privateMessage: target.privateMessage,
          );
        } on WriteException catch (error) {
          if (error.failure == WriteFailure.unreachable && !error.notSent) {
            invalidateDestination();
          }
          rethrow;
        } catch (_) {
          invalidateDestination();
          rethrow;
        }
        invalidateDestination();
        return destinationUrl;
      case _MoveSelectedPostsToNew(
        :final target,
        :final title,
        :final categoryId,
        :final tagIds,
      ):
        return api.movePosts(
          siteUrl: siteUrl,
          apiKey: apiKey,
          topicId: topicId,
          postIds: ids,
          title: title,
          categoryId: categoryId,
          tagIds: tagIds,
          privateMessage: target.privateMessage,
        );
      case _ChangeSelectedPostsOwner(:final username):
        await api.changePostOwners(
          siteUrl: siteUrl,
          apiKey: apiKey,
          topicId: topicId,
          postIds: ids,
          username: username,
        );
        return null;
    }
  }

  Future<({PostMutationOutcome outcome, String? destinationUrl})>
  _runSelectedPosts(_SelectedPostsCommand command, List<Post> posts) async {
    final siteUrl = command.siteUrl;
    final topicId = command.topicId;
    final lease = command.lease;
    final data = topicData.forLease(siteUrl, lease);
    if (data == null || _disposed) {
      return (outcome: const PostMutationRetired(), destinationUrl: null);
    }
    final ids = List<int>.unmodifiable(posts.map((post) => post.id));
    if (_selectedPostsDispatchBlock(command, ids) case final refusal?) {
      return (outcome: refusal, destinationUrl: null);
    }
    final unresolved = data.moderationRecoveryFor(topicId, ids);
    if (unresolved != null) {
      return (
        outcome: PostMutationNotSent.recoveryRequired(unresolved),
        destinationUrl: null,
      );
    }
    final selection = _selectedPosts[command.key]!;
    if (selection.active != null || ids.any(data.postWriting)) {
      return (
        outcome: const PostMutationNotSent(
          PostMutationProblem(PostMutationProblemKind.busyPost),
        ),
        destinationUrl: null,
      );
    }
    final attempt = _SelectedPostsAttempt(
      command: command,
      selection: selection,
      postIds: ids,
      data: data,
      releases: [
        for (final id in ids) data.holdPostWrite(id, notifyOnRelease: false),
      ],
    );
    selection.active = attempt;
    changed();
    PostMutationOutcome outcome = const PostMutationRetired();
    String? destinationUrl;
    ({PostMutationOutcome outcome, String? destinationUrl}) settle(
      PostMutationOutcome settled,
    ) {
      outcome = settled;
      return (outcome: settled, destinationUrl: destinationUrl);
    }

    try {
      if (!data.isCurrent || _disposed) return settle(outcome);
      if (_selectedPostsDispatchBlock(command, attempt.postIds)
          case final refusal?) {
        return settle(refusal);
      }
      final credential = await _credentialForWrite(siteUrl, lease: lease);
      if (!data.isCurrent || _disposed) return settle(outcome);
      if (_selectedPostsDispatchBlock(command, attempt.postIds)
          case final refusal?) {
        return settle(refusal);
      }
      if (credential.failure case final failure?) {
        return settle(PostMutationNotSent(policy.problem(failure)));
      }
      var sent = false;
      try {
        destinationUrl = await credential.request!.run(() {
          sent = true;
          return _sendSelectedPosts(attempt, credential.apiKey!);
        });
      } catch (error, stackTrace) {
        return settle(
          await policy.failed(
            data,
            topicId,
            attempt.postIds,
            credential.apiKey,
            error,
            stackTrace,
            sent: sent,
          ),
        );
      }
      outcome = const PostMutationAccepted.retired();
      if (!data.isCurrent || _disposed) return settle(outcome);
      final projection = await data.repairSelectedPosts(
        topicId,
        attempt.postIds,
        credential.apiKey,
        lease,
      );
      return settle(
        policy.accepted(
          projection,
          data.postMutationRecovery(
            topicId,
            attempt.postIds,
            credential.apiKey,
          ),
        ),
      );
    } finally {
      lease.commit(() {
        if (!identical(_selectedPosts[command.key], attempt.selection) ||
            !identical(selection.active, attempt)) {
          return;
        }
        selection.active = null;
        if (outcome is PostMutationAccepted ||
            outcome is PostMutationUncertain) {
          _selectedPosts.remove(command.key);
        }
        attempt.releaseHolds();
        changed();
      });
      attempt.releaseHolds();
    }
  }

  Future<_ShellWriteCredential> _credentialForWrite(
    String siteUrl, {
    required SiteLease lease,
  }) async {
    try {
      final session = AccountRequestSession(siteUrl, lease);
      final request = await session.keyCredentials(credentials);
      final apiKey = request.apiKey;
      return apiKey == null
          ? (
              apiKey: null,
              request: null,
              failure: const WriteException(WriteFailure.forbidden),
            )
          : (apiKey: apiKey, request: request, failure: null);
    } catch (error) {
      return (
        apiKey: null,
        request: null,
        failure: const WriteException(WriteFailure.unreachable),
      );
    }
  }
}
