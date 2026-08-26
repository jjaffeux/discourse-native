import '../../data/discourse_api_contracts.dart';
import '../../models/post.dart';
import '../../shell/shell_controller.dart';
import 'poll.dart';
import 'poll_api.dart';
import 'polls_api.dart';

/// What a native poll write learned.
///
/// [reconciled] means the write response was unreachable and the owning post
/// was read again. Presentation must discard its optimistic local selection,
/// even when the refetched saved selection happens to equal the old one.
final class PollVoteWriteResult {
  const PollVoteWriteResult.saved() : message = null, reconciled = false;

  const PollVoteWriteResult.reconciled() : message = null, reconciled = true;

  const PollVoteWriteResult.refused(this.message) : reconciled = false;

  final String? message;
  final bool reconciled;
}

/// Poll's typed interaction API over core's plugin-neutral write host.
extension PollShellExtension on ShellController {
  Future<PollVoteWriteResult> castPollVote(
    Post post,
    Poll poll,
    List<String> optionIds, {
    String? siteUrl,
  }) => _writePollVote(
    post,
    poll,
    options: List.unmodifiable(optionIds),
    siteUrl: siteUrl,
  );

  Future<PollVoteWriteResult> removePollVote(
    Post post,
    Poll poll, {
    String? siteUrl,
  }) => _writePollVote(post, poll, options: null, siteUrl: siteUrl);

  Future<PollVoteWriteResult> _writePollVote(
    Post post,
    Poll poll, {
    required List<String>? options,
    String? siteUrl,
  }) async {
    final targetSite = siteUrl ?? currentInstance?.url;
    final topicId = currentContent?.topicId;
    if (targetSite == null || topicId == null || !poll.isOpen) {
      return const PollVoteWriteResult.saved();
    }
    final detail = store.read<TopicDetail>(targetSite, topicId);
    if (detail?.archived == true) {
      return const PollVoteWriteResult.refused(
        'Voting is unavailable in archived topics.',
      );
    }

    if (!beginPluginPostWrite(targetSite, post.id)) {
      return const PollVoteWriteResult.reconciled();
    }
    final lease = lifecycle.capture(targetSite);
    try {
      final credential = await pluginWriteCredential(targetSite);
      if (!lease.isCurrent) return const PollVoteWriteResult.saved();
      if (credential.failure case final failure?) {
        return PollVoteWriteResult.refused(failure.message);
      }
      final apiKey = credential.apiKey!;
      final pollApi = api is PollsApi ? api as PollsApi : PollApi(api);

      final PollVoteResponse answer;
      try {
        answer = options == null
            ? await pollApi.removePollVote(
                siteUrl: targetSite,
                apiKey: apiKey,
                postId: post.id,
                pollName: poll.name,
              )
            : await pollApi.votePoll(
                siteUrl: targetSite,
                apiKey: apiKey,
                postId: post.id,
                pollName: poll.name,
                options: options,
              );
      } on WriteException catch (error) {
        if (error.failure != WriteFailure.unreachable) {
          return PollVoteWriteResult.refused(error.message);
        }
        await refreshPluginPost(targetSite, topicId, post.id, apiKey, lease);
        return const PollVoteWriteResult.reconciled();
      } catch (_) {
        await refreshPluginPost(targetSite, topicId, post.id, apiKey, lease);
        return const PollVoteWriteResult.reconciled();
      }

      lease.commit(() {
        store.update<Post>(targetSite, post.id, (held) {
          final polls = held.polls ?? const Polls();
          return held.withPlugins(
            held.plugins.withValue(pollsDataKey, polls.withPoll(answer.poll)),
          );
        });
        notifyPluginStateChanged();
      });
      return const PollVoteWriteResult.saved();
    } finally {
      lease.commit(() => endPluginPostWrite(targetSite, post.id));
    }
  }
}
