import 'package:discourse_native/discourse_plugin_sdk.dart';

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

  Future<String?> change({
    required String siteUrl,
    required TopicDetail topic,
    required int postId,
    required bool accepted,
    required PluginSiteLease lease,
  }) async {
    bool current() => !_closed && lease.isCurrent;
    final post = posts.readPost(siteUrl, postId);
    if (!current() ||
        post == null ||
        !canChange(post, accepted) ||
        !posts.beginWrite(siteUrl, postId)) {
      return null;
    }
    try {
      final credential = await requests.writeCredentialFor(siteUrl);
      if (!current()) return null;
      if (credential.failure case final failure?) return failure.message;
      final latest = posts.readPost(siteUrl, postId);
      if (latest == null || !canChange(latest, accepted)) return null;
      try {
        // Solved returns an accepted-answer array (or null). The shared write
        // transport validates status; fresh guardian-filtered records are the
        // source of truth, including a formerly accepted answer on this topic.
        await transport.pluginWriteJson(
          siteUrl: siteUrl,
          path: accepted ? '/solution/accept.json' : '/solution/unaccept.json',
          method: 'POST',
          apiKey: credential.apiKey!,
          body: {'id': postId},
        );
        if (!current()) return null;
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
          if (!current()) return null;
          await posts.refreshPost(
            siteUrl: siteUrl,
            topicId: topic.id,
            postId: id,
            apiKey: credential.apiKey,
            lease: lease,
          );
        }
        if (current()) await topics.reloadTopic(siteUrl, topic.id);
      } on WriteException catch (error) {
        if (current()) return error.message;
      } catch (_) {
        if (current()) {
          return const WriteException(WriteFailure.unreachable).message;
        }
      }
      return null;
    } finally {
      lease.commit(() => posts.endWrite(siteUrl, postId));
    }
  }
}
