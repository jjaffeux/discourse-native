import '../models/post.dart';
import '../models/post_likers.dart';
import '../models/post_revision.dart';

abstract interface class TopicContentApi {
  /// Fetches the post window around [postNumber]. Completing [abortTrigger]
  /// cancels this request, including while it waits for a network slot.
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  });

  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  });

  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  });

  /// Reads a page of posts after [postNumber], or before it unless
  /// [ascending], answered in topic order. This is how a mega topic pages
  /// (TopicDetail.isMegaTopic): it has no stream of ids to ask for.
  Future<List<Post>> postsFromNumber({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    required bool ascending,
    String? apiKey,
    String? clientId,
  });

  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  });

  Future<PostRevision> postRevision({
    required String siteUrl,
    required int postId,
    int? revision,
    String? apiKey,
    String? clientId,
  });
}
