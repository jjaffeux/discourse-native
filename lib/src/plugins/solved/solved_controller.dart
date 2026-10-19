import 'package:discourse_native/discourse_plugin_sdk.dart';

import 'solved_change_result.dart';
import 'solved_post.dart';

final class SolvedController {
  SolvedController({
    required this.transport,
    required this.requests,
    required this.posts,
    required this.topics,
  });
  final PluginApiTransport transport;
  final PluginRequestHost requests;
  final PluginPostHost posts;
  final PluginTopicRefreshHost topics;
  bool _closed = false;

  void close() => _closed = true;

  bool canChange(Post post, bool accepted) {
    final state = post.plugins.get(solvedPostKey);
    return !_closed &&
        post.postNumber != 1 &&
        !post.isWhisper &&
        !post.hidden &&
        !post.isDeleted &&
        state != null &&
        state.accepted != accepted &&
        (accepted ? state.canAccept : state.canUnaccept);
  }

  Future<SolvedChangeResult> change({
    required String siteUrl,
    required TopicDetail topic,
    required int postId,
    required bool accepted,
    required PluginSiteLease lease,
  }) async {
    bool current() => !_closed && lease.isCurrent;
    if (!current()) return const SolvedChangeResult.inactive();
    final post = posts.readPost(siteUrl, postId);
    if (post == null || !canChange(post, accepted)) {
      return const SolvedChangeResult.unchanged();
    }
    if (!posts.beginWrite(siteUrl, postId)) {
      return const SolvedChangeResult.busy();
    }
    try {
      PluginWriteCredential credential;
      try {
        credential = await requests.writeCredentialFor(siteUrl);
      } on WriteException catch (error) {
        return SolvedChangeResult.notSent(error, isCurrent: current());
      } catch (error, stackTrace) {
        return SolvedChangeResult.notSent(
          WriteException(
            WriteFailure.unreachable,
            notSent: true,
            cause: error,
            causeStackTrace: stackTrace,
          ),
          isCurrent: current(),
        );
      }
      if (!current()) return const SolvedChangeResult.inactive();
      if (credential.failure case final failure?) {
        return failure.failure == WriteFailure.unreachable || failure.notSent
            ? SolvedChangeResult.notSent(failure, isCurrent: true)
            : SolvedChangeResult.refused(failure, isCurrent: true);
      }
      final latest = posts.readPost(siteUrl, postId);
      if (latest == null || !canChange(latest, accepted)) {
        return const SolvedChangeResult.unchanged();
      }
      var dispatched = false;
      try {
        // Solved returns an accepted-answer array (or null). Guardian-filtered
        // records remain the source of truth, including a formerly accepted
        // answer on this topic.
        await credential.credentials!.run(() {
          dispatched = true;
          return transport.pluginWriteJson(
            siteUrl: siteUrl,
            path: accepted
                ? '/solution/accept.json'
                : '/solution/unaccept.json',
            method: 'POST',
            apiKey: credential.credentials!.apiKey!,
            body: {'id': postId},
          );
        });
      } on WriteException catch (error) {
        if (!dispatched || error.notSent) {
          return SolvedChangeResult.notSent(error, isCurrent: current());
        }
        return error.failure == WriteFailure.unreachable
            ? SolvedChangeResult.uncertain(error, isCurrent: current())
            : SolvedChangeResult.refused(error, isCurrent: current());
      } catch (error, stackTrace) {
        final failure = WriteException(
          WriteFailure.unreachable,
          notSent: !dispatched,
          cause: error,
          causeStackTrace: stackTrace,
        );
        return dispatched
            ? SolvedChangeResult.uncertain(failure, isCurrent: current())
            : SolvedChangeResult.notSent(failure, isCurrent: current());
      }
      if (!current()) return const SolvedChangeResult.acceptedRetired();
      try {
        final refreshIds = <int>{
          postId,
          for (final id in topic.stream)
            if (posts
                    .readPost(siteUrl, id)
                    ?.plugins
                    .get(solvedPostKey)
                    ?.accepted ==
                true)
              id,
        };
        for (final id in refreshIds) {
          if (!current()) return const SolvedChangeResult.acceptedRetired();
          await posts.refreshPost(
            siteUrl: siteUrl,
            topicId: topic.id,
            postId: id,
            apiKey: credential.credentials!.apiKey,
            lease: lease,
          );
        }
        if (!current()) return const SolvedChangeResult.acceptedRetired();
        await topics.reloadTopic(siteUrl, topic.id);
      } on WriteException catch (error) {
        return current()
            ? SolvedChangeResult.acceptedRefreshFailed(error)
            : const SolvedChangeResult.acceptedRetired();
      } catch (error, stackTrace) {
        return current()
            ? SolvedChangeResult.acceptedRefreshFailed(
                WriteException(
                  WriteFailure.unreachable,
                  cause: error,
                  causeStackTrace: stackTrace,
                ),
              )
            : const SolvedChangeResult.acceptedRetired();
      }
      return current()
          ? const SolvedChangeResult.applied()
          : const SolvedChangeResult.acceptedRetired();
    } finally {
      lease.commit(() => posts.endWrite(siteUrl, postId));
    }
  }
}
