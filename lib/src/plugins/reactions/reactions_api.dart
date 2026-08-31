import '../../models/post.dart';
import 'post_reactors.dart';

abstract interface class ReactionsApi {
  Future<PostReactors> postReactors({
    required String siteUrl,
    required int postId,
    String? reaction,
    int limit = 30,
    String? apiKey,
    String? clientId,
  });
}

abstract interface class ReactionsWriteApi {
  Future<Post?> toggleReaction({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String reaction,
    String? clientId,
  });
}
