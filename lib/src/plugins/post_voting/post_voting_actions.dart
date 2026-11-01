import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/l10n/strings.dart';

import 'post_voting_api.dart';
import 'post_voting_data.dart';

enum PostVotingWritePhase { idle, sending, refreshing, uncertain }

final class PostVotingWriteState {
  const PostVotingWriteState({
    this.phase = PostVotingWritePhase.idle,
    this.error,
    this.desiredDirection,
    this.originalDirection,
    this.optimistic = false,
  });
  final PostVotingWritePhase phase;
  final Object? error;
  final PostVoteDirection? desiredDirection;
  final PostVoteDirection? originalDirection;
  final bool optimistic;
  bool get pending =>
      phase == PostVotingWritePhase.sending ||
      phase == PostVotingWritePhase.refreshing;
  bool get uncertain => phase == PostVotingWritePhase.uncertain;
}

final class PostVotingCommentResult {
  const PostVotingCommentResult({this.accepted = false, this.error});
  final bool accepted;
  final Object? error;
}

typedef _Target = ({String site, int post});

final class PostVotingActions extends FrameSafeNotifier {
  PostVotingActions({
    required this.api,
    required this.requests,
    required this.posts,
    required this.settingsFor,
  });
  final PostVotingApi api;
  final PluginRequestHost requests;
  final PluginPostHost posts;
  final PostVotingSettings Function(String) settingsFor;
  final Map<_Target, PostVotingWriteState> _votes = {};
  final Map<_Target, PostVotingWriteState> _comments = {};
  final Map<(_Target, bool), Object> _runs = {};
  final Map<_Target, int> _commentRevisions = {};
  final Map<String, int> _epochs = {};
  int epochFor(String site) => _epochs[site] ?? 0;
  void invalidateComments(String site, int id) {
    final target = (site: site, post: id);
    _commentRevisions[target] = (_commentRevisions[target] ?? 0) + 1;
  }

  PostVotingWriteState voteState(String site, int id) =>
      _votes[(site: site, post: id)] ?? const PostVotingWriteState();
  PostVotingWriteState commentState(String site, int id) =>
      _comments[(site: site, post: id)] ?? const PostVotingWriteState();
  PostVotingPostData? record(String site, int id) =>
      posts.readPost(site, id)?.plugins.get(postVotingPostKey);
  PostVotingPostData? displayedRecord(String site, int id) {
    final held = record(site, id);
    final state = voteState(site, id);
    if (held == null || !state.optimistic) return held;
    int value(PostVoteDirection? direction) => switch (direction) {
      PostVoteDirection.up => 1,
      PostVoteDirection.down => -1,
      null => 0,
    };
    return held.withVote(
      score:
          (held.score ?? 0) +
          value(state.desiredDirection) -
          value(state.originalDirection),
      hasVotes: held.hasVotes == true || state.desiredDirection != null,
      myVote: state.desiredDirection,
      myVoteKnown: true,
    );
  }

  bool available(PluginTopicReader reader) =>
      !isDisposed &&
      reader.isCurrent &&
      settingsFor(reader.siteUrl).enabled != false &&
      reader.topic?.plugins.get(postVotingTopicKey)?.enabled == true;
  bool canVote(PluginTopicReader reader, int id) {
    final post = reader.post(id);
    return available(reader) &&
        reader.currentUserId != null &&
        post != null &&
        !post.contentRedacted &&
        !post.isDeleted &&
        post.userId != reader.currentUserId &&
        reader.topic?.closed != true &&
        reader.topic?.archived != true &&
        record(reader.siteUrl, id)?.myVoteKnown == true;
  }

  void _set(
    _Target target,
    PostVotingWriteState state, {
    bool comment = false,
  }) {
    (comment ? _comments : _votes)[target] = state;
    notifySafely();
  }

  bool _current(
    PluginTopicReader reader,
    PluginSiteLease lease,
    _Target target,
    Object run, {
    bool comment = false,
  }) =>
      available(reader) &&
      lease.isCurrent &&
      identical(_runs[(target, comment)], run);

  Future<bool> reconcilePost(PluginTopicReader reader, int postId) async {
    if (!available(reader)) return false;
    final number = reader.post(postId)?.postNumber;
    final receipt = await reader.ingest((credentials) async {
      final window = await api.loadWindow(
        siteUrl: reader.siteUrl,
        topicId: reader.topicId,
        order: PostVotingOrder.votes,
        credentials: credentials,
        nearPostNumber: number,
        heldTopic: reader.topic,
      );
      return TopicContentResult(
        value: window,
        posts: window.posts,
        metadata: window.metadata,
      );
    });
    final incoming = receipt?.value.posts
        .where((item) => item.post.id == postId)
        .firstOrNull
        ?.post
        .plugins
        .get(postVotingPostKey);
    final canonical = record(reader.siteUrl, postId);
    return available(reader) &&
        receipt?.postIds.contains(postId) == true &&
        !posts.writeInFlight(reader.siteUrl, postId) &&
        incoming != null &&
        canonical != null &&
        incoming.score == canonical.score &&
        incoming.hasVotes == canonical.hasVotes &&
        incoming.myVoteKnown == canonical.myVoteKnown &&
        incoming.myVote == canonical.myVote;
  }

  Future<String?> vote(
    PluginTopicReader reader,
    int id,
    PostVoteDirection? desired,
  ) async {
    final target = (site: reader.siteUrl, post: id);
    if (!canVote(reader, id) ||
        voteState(target.site, id).pending ||
        voteState(target.site, id).uncertain) {
      return null;
    }
    final lease = requests.capture(target.site), run = Object();
    if (!lease.isCurrent || !posts.beginWrite(target.site, id)) return null;
    if (!lease.isCurrent || !available(reader)) {
      if (lease.isCurrent) posts.endWrite(target.site, id);
      return null;
    }
    var ownsLane = true;
    void releaseLane() {
      if (ownsLane && lease.isCurrent) {
        ownsLane = false;
        posts.endWrite(target.site, id);
      }
    }

    _runs[(target, false)] = run;
    final original = record(target.site, id)?.myVote;
    var sent = false;
    try {
      if (!_current(reader, lease, target, run)) return null;
      _set(
        target,
        PostVotingWriteState(
          phase: PostVotingWritePhase.sending,
          desiredDirection: desired,
          originalDirection: original,
          optimistic: true,
        ),
      );
      if (!_current(reader, lease, target, run)) return null;
      final write = await requests.writeCredentialFor(target.site);
      if (!_current(reader, lease, target, run)) return null;
      if (write.failure != null || write.credentials == null) {
        throw write.failure ?? const WriteException(WriteFailure.forbidden);
      }
      sent = true;
      if (desired == null) {
        await api.undoPostVote(
          siteUrl: target.site,
          postId: id,
          credentials: write.credentials!,
        );
      } else {
        await api.votePost(
          siteUrl: target.site,
          postId: id,
          direction: desired,
          credentials: write.credentials!,
        );
      }
      if (!_current(reader, lease, target, run)) return null;
      _set(
        target,
        const PostVotingWriteState(phase: PostVotingWritePhase.refreshing),
      );
      releaseLane();
      if (!await reconcilePost(reader, id)) {
        throw const WriteException(WriteFailure.unreachable);
      }
      if (_current(reader, lease, target, run)) {
        _set(target, const PostVotingWriteState());
      }
      return null;
    } catch (error) {
      if (!_current(reader, lease, target, run)) return null;
      final uncertain =
          sent &&
          !(error is WriteException &&
              (error.notSent || error.failure != WriteFailure.unreachable));
      _set(
        target,
        PostVotingWriteState(
          phase: uncertain
              ? PostVotingWritePhase.uncertain
              : PostVotingWritePhase.idle,
          error: error,
        ),
      );
      releaseLane();
      if (!uncertain) {
        try {
          await reconcilePost(reader, id);
        } catch (_) {
          /* Keep the original refusal. */
        }
      }
      return uncertain ? appL10n.postVotingUncertain : postVotingError(error);
    } finally {
      if (lease.isCurrent && identical(_runs[(target, false)], run)) {
        _runs.remove((target, false));
        releaseLane();
      }
    }
  }

  Future<void> checkVote(PluginTopicReader reader, int id) async {
    if (!available(reader) || voteState(reader.siteUrl, id).pending) return;
    final target = (site: reader.siteUrl, post: id);
    try {
      if (await reconcilePost(reader, id)) {
        _set(target, const PostVotingWriteState());
      }
    } catch (error) {
      if (available(reader)) {
        _set(
          target,
          PostVotingWriteState(
            phase: PostVotingWritePhase.uncertain,
            error: error,
          ),
        );
      }
    }
  }

  void votedEvent(PluginTopicReader reader, Map<Object?, Object?> event) {
    if (!available(reader)) return;
    final id = event['id'],
        score = event['post_voting_vote_count'],
        hasVotes = event['post_voting_has_votes'];
    if (id is! int ||
        id <= 0 ||
        score is! int ||
        hasVotes is! bool ||
        reader.post(id) == null) {
      return;
    }
    final mine =
        event['post_voting_user_voted_id'] == reader.currentUserId &&
        reader.currentUserId != null;
    if (mine &&
        event['post_voting_user_voted_direction'] != null &&
        PostVoteDirection.parse(event['post_voting_user_voted_direction']) ==
            null) {
      return;
    }
    final target = (site: reader.siteUrl, post: id),
        state = voteState(reader.siteUrl, id);
    if (mine && state.optimistic) {
      _votes[target] = PostVotingWriteState(phase: state.phase);
    }
    posts.updatePluginRecord(
      reader.siteUrl,
      id,
      postVotingPostKey,
      (held) => held?.withVote(
        score: score,
        hasVotes: hasVotes,
        myVote: mine
            ? PostVoteDirection.parse(event['post_voting_user_voted_direction'])
            : held.myVote,
        myVoteKnown: mine || held.myVoteKnown,
      ),
    );
    if (mine && state.optimistic) notifySafely();
  }

  Future<PostVotingCommentBatch?> loadComments(
    PluginTopicReader reader,
    int postId, {
    int afterId = 0,
  }) async {
    if (!available(reader)) return null;
    final lease = requests.capture(reader.siteUrl);
    final epoch = epochFor(reader.siteUrl);
    final target = (site: reader.siteUrl, post: postId);
    final revision = _commentRevisions[target] ?? 0;
    final credentials = await requests.credentialsFor(reader.siteUrl);
    if (!lease.isCurrent || !available(reader)) return null;
    final result = await api.comments(
      siteUrl: reader.siteUrl,
      postId: postId,
      afterCommentId: afterId,
      credentials: credentials,
    );
    if (!lease.isCurrent ||
        !available(reader) ||
        epoch != epochFor(reader.siteUrl) ||
        revision != (_commentRevisions[target] ?? 0)) {
      return null;
    }
    return result;
  }

  void publishComments(
    PluginTopicReader reader,
    int id,
    List<PostVotingComment> comments, {
    required int total,
  }) {
    if (!available(reader)) return;
    posts.updatePluginRecord(
      reader.siteUrl,
      id,
      postVotingPostKey,
      (held) => held?.withComments(comments, total: total),
    );
  }

  Future<void> checkComments(PluginTopicReader reader, int id) async {
    if (!available(reader) || commentState(reader.siteUrl, id).pending) return;
    try {
      final result = await loadComments(reader, id);
      if (result != null) {
        publishComments(
          reader,
          id,
          result.comments,
          total: result.comments.length,
        );
        _set(
          (site: reader.siteUrl, post: id),
          const PostVotingWriteState(),
          comment: true,
        );
      }
    } catch (error) {
      if (available(reader)) {
        _set(
          (site: reader.siteUrl, post: id),
          PostVotingWriteState(
            phase: PostVotingWritePhase.uncertain,
            error: error,
          ),
          comment: true,
        );
      }
    }
  }

  Future<PostVotingCommentResult> mutateComment({
    required PluginTopicReader reader,
    required int postId,
    required Future<PostVotingComment?> Function(PluginRequestCredentials) send,
  }) async {
    final target = (site: reader.siteUrl, post: postId);
    final heldState = commentState(target.site, postId);
    if (!available(reader) ||
        reader.currentUserId == null ||
        heldState.pending ||
        heldState.uncertain ||
        !settingsFor(target.site).commentsEnabled) {
      return const PostVotingCommentResult();
    }
    final run = Object(), lease = requests.capture(target.site);
    invalidateComments(target.site, postId);
    _runs[(target, true)] = run;
    _set(
      target,
      const PostVotingWriteState(phase: PostVotingWritePhase.sending),
      comment: true,
    );
    var sent = false, accepted = false;
    try {
      final write = await requests.writeCredentialFor(target.site);
      if (!_current(reader, lease, target, run, comment: true)) {
        return const PostVotingCommentResult();
      }
      if (write.failure != null || write.credentials == null) {
        throw write.failure ?? const WriteException(WriteFailure.forbidden);
      }
      sent = true;
      final returned = await send(write.credentials!);
      accepted = true;
      if (!_current(reader, lease, target, run, comment: true)) {
        return const PostVotingCommentResult(accepted: true);
      }
      if (returned != null) {
        final held = record(target.site, postId),
            entries = held?.initialComments ?? const <PostVotingComment>[];
        if (entries.any((entry) => entry.id == returned.id)) {
          publishComments(reader, postId, [
            for (final entry in entries)
              entry.id == returned.id ? returned : entry,
          ], total: held?.commentsCount ?? entries.length);
        } else if (entries.length == held?.commentsCount) {
          publishComments(reader, postId, [
            ...entries,
            returned,
          ], total: entries.length + 1);
        }
      }
      _set(
        target,
        const PostVotingWriteState(phase: PostVotingWritePhase.refreshing),
        comment: true,
      );
      final comments = await loadComments(reader, postId);
      if (!_current(reader, lease, target, run, comment: true)) {
        return const PostVotingCommentResult(accepted: true);
      }
      if (comments == null) {
        throw const WriteException(WriteFailure.unreachable);
      }
      publishComments(
        reader,
        postId,
        comments.comments,
        total: comments.comments.length,
      );
      _set(target, const PostVotingWriteState(), comment: true);
      return const PostVotingCommentResult(accepted: true);
    } catch (error) {
      if (!_current(reader, lease, target, run, comment: true)) {
        return PostVotingCommentResult(accepted: accepted);
      }
      final uncertain =
          accepted ||
          sent &&
              !(error is WriteException &&
                  (error.notSent || error.failure != WriteFailure.unreachable));
      _set(
        target,
        PostVotingWriteState(
          phase: uncertain
              ? PostVotingWritePhase.uncertain
              : PostVotingWritePhase.idle,
          error: error,
        ),
        comment: true,
      );
      return PostVotingCommentResult(accepted: accepted, error: error);
    } finally {
      if (lease.isCurrent && identical(_runs[(target, true)], run)) {
        _runs.remove((target, true));
      }
    }
  }

  void forget(String site) {
    _epochs[site] = epochFor(site) + 1;
    _commentRevisions.removeWhere((key, _) => key.site == site);
    _votes.removeWhere((key, _) => key.site == site);
    _comments.removeWhere((key, _) => key.site == site);
    _runs.removeWhere((key, _) => key.$1.site == site);
    notifySafely();
  }
}

String postVotingError(Object error) =>
    error is WriteException ? error.message : appL10n.couldnTReachTheSite;
