import 'poll.dart';

/// Personalized writes owned by Discourse's bundled Poll plugin.
abstract interface class PollsApi {
  Future<PollVoteResponse> votePoll({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    required List<String> options,
    String? clientId,
  });

  Future<PollVoteResponse> removePollVote({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    String? clientId,
  });
}
