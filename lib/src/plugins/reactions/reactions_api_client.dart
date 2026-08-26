import '../../data/plugin_transport.dart';
import '../../models/post.dart';
import '../discourse_model_codec.dart';
import 'post_reactors.dart';
import 'reactions_api.dart';

final class ReactionsApiClient implements ReactionsApi, ReactionsWriteApi {
  const ReactionsApiClient(this._transport, this._models);

  final PluginApiTransport _transport;
  final DiscourseModelCodec _models;

  @override
  Future<PostReactors> postReactors({
    required String siteUrl,
    required int postId,
    String? reaction,
    int limit = 30,
    String? apiKey,
    String? clientId,
  }) async {
    _requirePositiveId(postId);
    if (limit < 1 || limit > PostReactors.maximumPageSize) {
      throw RangeError.range(limit, 1, PostReactors.maximumPageSize, 'limit');
    }
    if (reaction != null) _validateReaction(reaction);
    final path = Uri(
      path: '/discourse-reactions/posts/$postId/reactions-users-list.json',
      queryParameters: {'limit': '$limit', 'reaction_value': ?reaction},
    ).toString();
    final body = await _transport.pluginGetJson(
      siteUrl: siteUrl,
      path: path,
      apiKey: apiKey,
      clientId: clientId,
    );
    return PostReactors.parse(
      body,
      postId: postId,
      siteUrl: siteUrl,
      filter: reaction,
    );
  }

  @override
  Future<Post?> toggleReaction({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String reaction,
    String? clientId,
  }) async {
    _requirePositiveId(postId);
    _validateReaction(reaction);
    final body = await _transport.pluginWriteJson(
      siteUrl: siteUrl,
      path:
          '/discourse-reactions/posts/$postId/custom-reactions/'
          '${Uri.encodeComponent(reaction)}/toggle.json',
      method: 'PUT',
      apiKey: apiKey,
      body: const {},
      clientId: clientId,
    );
    return body['id'] == null ? null : _models.post(body, siteUrl);
  }

  static void _requirePositiveId(int value) {
    if (value <= 0) {
      throw RangeError.value(value, 'postId', 'Must be positive.');
    }
  }

  static void _validateReaction(String reaction) {
    if (reaction.isEmpty || reaction.length > 100) {
      throw ArgumentError.value(reaction, 'reaction');
    }
  }
}
